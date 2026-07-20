using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Pruebas de integración reales contra ActivityAttachmentsController/AttachmentService
// + fn_create_activity_attachment / fn_list_activity_attachments /
// fn_get_activity_attachment / fn_delete_activity_attachment (SPEC-002, db/06_*.sql).
// Se salta (no falla) sin un Postgres alcanzable — mismo patrón que
// ActivityServiceTests (§25 / DatabaseFixture).
[Collection("Database")]
public class AttachmentServiceTests : IDisposable
{
    private readonly DatabaseFixture _fixture;
    private readonly AttachmentService _attachmentService = null!;
    private readonly ActivityService _activityService = null!;
    private readonly AuthService _authService = null!;
    private readonly string _storageRoot;

    public AttachmentServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
        _storageRoot = Path.Combine(Path.GetTempPath(), "omnitask-attachments-tests", Guid.NewGuid().ToString("N"));

        if (!fixture.IsAvailable) return;

        var fileStorage = new LocalFileStorage(new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Attachments:RootPath"] = _storageRoot,
            })
            .Build());

        _attachmentService = new AttachmentService(fixture.DataSource, fileStorage);
        _activityService = new ActivityService(fixture.DataSource);

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = "clave-de-prueba-de-al-menos-32-bytes!!",
            })
            .Build();
        _authService = new AuthService(fixture.DataSource, new Argon2PasswordHasher(), new JwtTokenFactory(config));
    }

    public void Dispose()
    {
        if (Directory.Exists(_storageRoot))
            Directory.Delete(_storageRoot, recursive: true);
    }

    private async Task<Guid> CreateTestUserAsync()
    {
        var registered = await _authService.RegisterAsync(new RegisterRequest(
            FullName: "Usuario de Prueba",
            Email: $"{Guid.NewGuid():N}@clinicacampbell.test",
            Password: "clave-segura-123",
            PhoneE164: "+573000000000",
            Timezone: "America/Bogota"));
        return registered.User.Id;
    }

    private async Task<Guid> CreateTestActivityAsync(Guid userId)
    {
        var created = await _activityService.CreateAsync(userId, new ActivityCreateRequest(
            Type: "meeting",
            Title: "Actividad con adjuntos",
            Description: null,
            ContactId: null,
            StartsAt: DateTimeOffset.UtcNow.AddDays(1),
            EndsAt: DateTimeOffset.UtcNow.AddDays(1).AddHours(1),
            Location: null));
        return created.Id;
    }

    private static MemoryStream MakeContent(int sizeBytes)
    {
        var bytes = new byte[sizeBytes];
        new Random(42).NextBytes(bytes);
        return new MemoryStream(bytes);
    }

    // CA2 (listar) + CA1: subir una imagen y un PDF, ambos aparecen en la lista.
    [SkippableFact]
    public async Task UploadAsync_y_ListAsync_devuelven_los_adjuntos_subidos()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        await using var imageContent = MakeContent(1024);
        await _attachmentService.UploadAsync(userId, activityId, "foto.jpg", "image/jpeg", imageContent);

        await using var pdfContent = MakeContent(2048);
        await _attachmentService.UploadAsync(userId, activityId, "informe.pdf", "application/pdf", pdfContent);

        var list = await _attachmentService.ListAsync(userId, activityId);

        Assert.Equal(2, list.Count);
        Assert.Contains(list, a => a.FileName == "foto.jpg" && a.ContentType == "image/jpeg" && a.SizeBytes == 1024);
        Assert.Contains(list, a => a.FileName == "informe.pdf" && a.ContentType == "application/pdf" && a.SizeBytes == 2048);
    }

    // CA3 + RNF3: la descarga entrega los mismos bytes que se subieron (integridad).
    [SkippableFact]
    public async Task DownloadAsync_devuelve_los_mismos_bytes_que_se_subieron()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        var originalBytes = new byte[5000];
        new Random(7).NextBytes(originalBytes);

        await using var uploadContent = new MemoryStream(originalBytes);
        var uploaded = await _attachmentService.UploadAsync(userId, activityId, "documento.pdf", "application/pdf", uploadContent);

        var (metadata, content) = await _attachmentService.DownloadAsync(userId, activityId, uploaded.Id);
        await using var downloadedStream = content;
        using var buffer = new MemoryStream();
        await downloadedStream.CopyToAsync(buffer);
        var downloadedBytes = buffer.ToArray();

        Assert.Equal("documento.pdf", metadata.FileName);
        Assert.Equal("application/pdf", metadata.ContentType);
        Assert.Equal(originalBytes.Length, downloadedBytes.Length);
        Assert.Equal(originalBytes, downloadedBytes);
    }

    // CA4: eliminar un adjunto lo quita de la lista y borra el archivo físico.
    [SkippableFact]
    public async Task DeleteAsync_quita_el_adjunto_de_la_lista_y_borra_el_archivo_fisico()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        await using var content = MakeContent(512);
        var uploaded = await _attachmentService.UploadAsync(userId, activityId, "borrar.png", "image/png", content);

        var physicalPath = Directory.GetFiles(_storageRoot, "*", SearchOption.AllDirectories).Single();
        Assert.True(File.Exists(physicalPath));

        await _attachmentService.DeleteAsync(userId, activityId, uploaded.Id);

        var list = await _attachmentService.ListAsync(userId, activityId);
        Assert.Empty(list);
        Assert.False(File.Exists(physicalPath));
    }

    // CA4: al eliminar/cancelar la actividad, sus adjuntos se borran en cascada (FK).
    [SkippableFact]
    public async Task CancelAsync_no_impide_verificar_cascada_de_adjuntos_al_borrar_la_actividad()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        await using var content = MakeContent(256);
        await _attachmentService.UploadAsync(userId, activityId, "cascada.png", "image/png", content);

        // El borrado en cascada (RF5, ON DELETE CASCADE en db/04_activity_attachments.sql)
        // se dispara al borrar la fila de `activities`, no al "cancelar" (soft-delete
        // vía status). Se ejercita el DELETE físico directamente contra la BD para
        // demostrar que la FK realmente limpia activity_attachments.
        await using var conn = await _fixture.DataSource.OpenConnectionAsync();
        await using (var deleteCmd = conn.CreateCommand())
        {
            deleteCmd.CommandText = "DELETE FROM activities WHERE id = @id";
            deleteCmd.Parameters.AddWithValue("id", activityId);
            var rows = await deleteCmd.ExecuteNonQueryAsync();
            Assert.Equal(1, rows);
        }

        await using var countCmd = conn.CreateCommand();
        countCmd.CommandText = "SELECT COUNT(*) FROM activity_attachments WHERE activity_id = @id";
        countCmd.Parameters.AddWithValue("id", activityId);
        var remaining = (long)(await countCmd.ExecuteScalarAsync())!;
        Assert.Equal(0, remaining);
    }

    // CA5: un archivo que "miente" en Content-Length (o no lo declara) pero supera
    // los 10 MB reales al leerse debe cortar la subida con 4xx (413), nunca colgar
    // el server ni lanzar una excepción sin capturar. Ejercita BoundedStream, la
    // pieza que protege este caso límite señalado por WOLVERINE además del chequeo
    // de RequestSizeLimit en el controlador (ver Api/ActivityAttachmentsControllerTests
    // más abajo para el límite de Kestrel).
    [SkippableFact]
    public async Task UploadAsync_con_stream_mayor_a_10MB_lanza_413_sin_excepcion_sin_capturar()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        const int elevenMb = 11 * 1024 * 1024;
        await using var oversizedContent = MakeContent(elevenMb);

        var ex = await Assert.ThrowsAsync<ApiException>(() =>
            _attachmentService.UploadAsync(userId, activityId, "grande.pdf", "application/pdf", oversizedContent));

        Assert.Equal(413, ex.StatusCode);

        // No debe quedar ni el registro de metadatos ni un archivo huérfano.
        var list = await _attachmentService.ListAsync(userId, activityId);
        Assert.Empty(list);
        Assert.False(Directory.Exists(_storageRoot) && Directory.GetFiles(_storageRoot, "*", SearchOption.AllDirectories).Any());
    }

    // CA6: tipo no permitido (ej. .exe) devuelve 4xx (415), nunca 500.
    [SkippableFact]
    public async Task UploadAsync_con_content_type_no_permitido_lanza_415()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        await using var content = MakeContent(128);
        var ex = await Assert.ThrowsAsync<ApiException>(() =>
            _attachmentService.UploadAsync(userId, activityId, "virus.exe", "application/x-msdownload", content));

        Assert.Equal(415, ex.StatusCode);
    }

    // CA6 (extensión incoherente): Content-Type permitido pero extensión que no
    // corresponde (defensa RF7/BLACK WIDOW R3) también debe rechazarse con 4xx.
    [SkippableFact]
    public async Task UploadAsync_con_extension_incoherente_con_el_content_type_lanza_415()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        await using var content = MakeContent(128);
        var ex = await Assert.ThrowsAsync<ApiException>(() =>
            _attachmentService.UploadAsync(userId, activityId, "documento.docx", "application/pdf", content));

        Assert.Equal(415, ex.StatusCode);
    }

    // CA7: un usuario no puede listar/descargar/eliminar adjuntos de actividades
    // de otro usuario — 404 (no revela existencia del recurso ajeno, RNF1).
    [SkippableFact]
    public async Task Operaciones_sobre_adjunto_de_otro_usuario_devuelven_404()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var ownerId = await CreateTestUserAsync();
        var otherUserId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(ownerId);

        await using var content = MakeContent(256);
        var uploaded = await _attachmentService.UploadAsync(ownerId, activityId, "privado.png", "image/png", content);

        var listEx = await Assert.ThrowsAsync<ApiException>(() => _attachmentService.ListAsync(otherUserId, activityId));
        Assert.Equal(404, listEx.StatusCode);

        var downloadEx = await Assert.ThrowsAsync<ApiException>(() =>
            _attachmentService.DownloadAsync(otherUserId, activityId, uploaded.Id));
        Assert.Equal(404, downloadEx.StatusCode);

        var deleteEx = await Assert.ThrowsAsync<ApiException>(() =>
            _attachmentService.DeleteAsync(otherUserId, activityId, uploaded.Id));
        Assert.Equal(404, deleteEx.StatusCode);

        // El adjunto del dueño real sigue intacto: el intento del otro usuario no lo tocó.
        var ownerList = await _attachmentService.ListAsync(ownerId, activityId);
        Assert.Single(ownerList);
    }

    // CA8: el nombre físico en disco es un GUID (con extensión derivada del
    // content_type), nunca el nombre original del cliente — verificable
    // inspeccionando storage_path (aquí, indirectamente: el archivo físico
    // creado por LocalFileStorage no se llama "nombre-original-con-espacios.png").
    [SkippableFact]
    public async Task UploadAsync_genera_nombre_fisico_GUID_distinto_del_nombre_del_cliente()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var activityId = await CreateTestActivityAsync(userId);

        const string originalFileName = "nombre original con espacios y ñ.png";
        await using var content = MakeContent(256);
        var uploaded = await _attachmentService.UploadAsync(userId, activityId, originalFileName, "image/png", content);

        // El DTO conserva el nombre original para mostrarlo al usuario (RF1)...
        Assert.Equal(originalFileName, uploaded.FileName);

        // ...pero el archivo físico en disco no usa ese nombre: debe ser un GUID.
        var physicalFiles = Directory.GetFiles(_storageRoot, "*", SearchOption.AllDirectories);
        var physicalFile = Assert.Single(physicalFiles);
        var physicalFileName = Path.GetFileNameWithoutExtension(physicalFile);

        Assert.True(Guid.TryParse(physicalFileName, out _),
            $"Se esperaba que el nombre físico '{physicalFileName}' fuera un GUID");
        Assert.NotEqual(Path.GetFileNameWithoutExtension(originalFileName), physicalFileName);
        Assert.Equal(".png", Path.GetExtension(physicalFile));
    }
}
