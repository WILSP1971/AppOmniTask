using Npgsql;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Infrastructure.Services;

// SPEC-002 (§3, §4 RNF6): capa Infrastructure — coordina validación,
// persistencia de metadatos (fn_* de db/06_*.sql) y el binario en
// filesystem (IFileStorage). El controlador (Api) queda delgado.
public class AttachmentService : SqlServiceBase, IAttachmentService
{
    private readonly IFileStorage _fileStorage;

    public AttachmentService(NpgsqlDataSource dataSource, IFileStorage fileStorage) : base(dataSource) =>
        _fileStorage = fileStorage;

    public async Task<AttachmentResponse> UploadAsync(
        Guid userId, Guid activityId, string fileName, string contentType, Stream content)
    {
        // RF7 / RNF1: validación de servidor, nunca confiar solo en el cliente.
        if (!AttachmentValidation.IsContentTypeAllowed(contentType))
            throw new ApiException(415, "unsupported_media_type", "Tipo de archivo no permitido");

        if (!AttachmentValidation.IsExtensionCoherent(contentType, fileName))
            throw new ApiException(415, "unsupported_media_type", "La extensión del archivo no coincide con su tipo");

        // Content-Length ya se valida en el controlador (413) antes de leer el
        // stream completo; aquí se vuelve a comprobar el tamaño real copiado
        // por si el header venía ausente o mentía.
        using var bounded = new BoundedStream(content, AttachmentValidation.MaxSizeBytes);

        await using var buffer = new MemoryStream();
        await bounded.CopyToAsync(buffer);

        if (bounded.LimitExceeded)
            throw new ApiException(413, "payload_too_large", "El archivo supera el tamaño máximo permitido (10 MB)");

        buffer.Position = 0;
        var storagePath = await _fileStorage.SaveAsync(buffer);

        return await RunAsync(async conn =>
        {
            try
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT * FROM fn_create_activity_attachment(@user_id, @activity_id, @file_name, @content_type, @size_bytes, @storage_path)";
                cmd.Parameters.AddWithValue("user_id", userId);
                cmd.Parameters.AddWithValue("activity_id", activityId);
                cmd.Parameters.AddWithValue("file_name", fileName);
                cmd.Parameters.AddWithValue("content_type", contentType);
                cmd.Parameters.AddWithValue("size_bytes", buffer.Length);
                cmd.Parameters.AddWithValue("storage_path", storagePath);

                await using var reader = await cmd.ExecuteReaderAsync();
                if (!await reader.ReadAsync())
                    throw new ApiException(404, "not_found", "Actividad no encontrada");
                return MapAttachment(reader);
            }
            catch
            {
                // Si el registro de metadatos falla (p. ej. actividad ajena),
                // no debe quedar un archivo físico huérfano.
                await _fileStorage.DeleteAsync(storagePath);
                throw;
            }
        });
    }

    public Task<List<AttachmentResponse>> ListAsync(Guid userId, Guid activityId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_list_activity_attachments(@user_id, @activity_id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("activity_id", activityId);

        var items = new List<AttachmentResponse>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync()) items.Add(MapAttachment(reader));
        return items;
    });

    public async Task<(AttachmentResponse Metadata, Stream Content)> DownloadAsync(
        Guid userId, Guid activityId, Guid attachmentId)
    {
        var metadata = await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_get_activity_attachment(@user_id, @activity_id, @attachment_id)";
            cmd.Parameters.AddWithValue("user_id", userId);
            cmd.Parameters.AddWithValue("activity_id", activityId);
            cmd.Parameters.AddWithValue("attachment_id", attachmentId);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
                throw new ApiException(404, "not_found", "Adjunto no encontrado");

            return (Response: MapAttachment(reader), StoragePath: reader.GetString(reader.GetOrdinal("storage_path")));
        });

        var content = await _fileStorage.OpenReadAsync(metadata.StoragePath);
        return (metadata.Response, content);
    }

    public Task DeleteAsync(Guid userId, Guid activityId, Guid attachmentId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_delete_activity_attachment(@user_id, @activity_id, @attachment_id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("activity_id", activityId);
        cmd.Parameters.AddWithValue("attachment_id", attachmentId);

        string storagePath;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync())
                throw new ApiException(404, "not_found", "Adjunto no encontrado");
            storagePath = reader.GetString(reader.GetOrdinal("storage_path"));
        }

        // Best-effort (RF5): el registro ya se borró en BD; si el archivo
        // físico no existe o falla el borrado, no se revierte la operación.
        try
        {
            await _fileStorage.DeleteAsync(storagePath);
        }
        catch (IOException)
        {
            // Limpieza física best-effort: no revierte el borrado del metadato.
        }
    });

    private static AttachmentResponse MapAttachment(NpgsqlDataReader reader) => new(
        reader.GetGuid(reader.GetOrdinal("id")),
        reader.GetGuid(reader.GetOrdinal("activity_id")),
        reader.GetString(reader.GetOrdinal("file_name")),
        reader.GetString(reader.GetOrdinal("content_type")),
        reader.GetInt64(reader.GetOrdinal("size_bytes")),
        reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("uploaded_at")));
}

// Envuelve un Stream y corta la lectura apenas se supera el límite, en vez de
// cargar un archivo arbitrariamente grande completo en memoria antes de
// rechazarlo (RNF2 / CA5: rechazar >10 MB sin degradar el servidor).
public class BoundedStream : Stream
{
    private readonly Stream _inner;
    private readonly long _maxBytes;
    private long _totalRead;

    public BoundedStream(Stream inner, long maxBytes)
    {
        _inner = inner;
        _maxBytes = maxBytes;
    }

    public bool LimitExceeded { get; private set; }

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        if (LimitExceeded) return 0;

        var read = await _inner.ReadAsync(buffer.AsMemory(offset, count), cancellationToken);
        _totalRead += read;
        if (_totalRead > _maxBytes)
        {
            LimitExceeded = true;
            return 0;
        }
        return read;
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override int Read(byte[] buffer, int offset, int count) =>
        ReadAsync(buffer, offset, count, CancellationToken.None).GetAwaiter().GetResult();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
