using Microsoft.Extensions.Configuration;

namespace OmniTask.Infrastructure.Services;

// SPEC-002 (§2 decisión arquitectónica, §4 RNF6): guarda/lee/borra bytes en
// el filesystem del servidor con ruta configurable (Attachments:RootPath).
// El nombre físico es SIEMPRE un GUID generado aquí — nunca el nombre
// original del cliente (defensa contra path traversal / colisiones, RNF1).
// La extensión sí se preserva (derivada del content_type ya validado por
// AttachmentValidation), solo para que el archivo sea identificable en el
// filesystem — no reintroduce el nombre del cliente ni afecta la defensa
// anti path-traversal.
public interface IFileStorage
{
    // Devuelve la ruta relativa (dentro de RootPath) donde quedó guardado el archivo.
    Task<string> SaveAsync(Stream content, string extension, CancellationToken cancellationToken = default);

    Task<Stream> OpenReadAsync(string relativePath, CancellationToken cancellationToken = default);

    Task DeleteAsync(string relativePath, CancellationToken cancellationToken = default);
}

public class LocalFileStorage : IFileStorage
{
    private readonly string _rootPath;

    public LocalFileStorage(IConfiguration configuration)
    {
        _rootPath = configuration["Attachments:RootPath"]
            ?? throw new InvalidOperationException("Falta configurar Attachments:RootPath");
        Directory.CreateDirectory(_rootPath);
    }

    public async Task<string> SaveAsync(Stream content, string extension, CancellationToken cancellationToken = default)
    {
        var safeExtension = extension.StartsWith('.') ? extension : $".{extension}";
        var relativePath = $"{Guid.NewGuid():N}{safeExtension}";
        var fullPath = ResolveFullPath(relativePath);

        await using var fileStream = new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await content.CopyToAsync(fileStream, cancellationToken);

        return relativePath;
    }

    public Task<Stream> OpenReadAsync(string relativePath, CancellationToken cancellationToken = default)
    {
        var fullPath = ResolveFullPath(relativePath);
        Stream stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Task.FromResult(stream);
    }

    public Task DeleteAsync(string relativePath, CancellationToken cancellationToken = default)
    {
        var fullPath = ResolveFullPath(relativePath);
        if (File.Exists(fullPath)) File.Delete(fullPath);
        return Task.CompletedTask;
    }

    // El nombre físico lo generamos siempre nosotros (SaveAsync), pero se
    // resuelve la ruta completa de forma defensiva por si en el futuro
    // storage_path llega de otro origen: nunca se permite escapar de
    // RootPath (anti path traversal, RNF1).
    private string ResolveFullPath(string relativePath)
    {
        var fullPath = Path.GetFullPath(Path.Combine(_rootPath, relativePath));
        var normalizedRoot = Path.GetFullPath(_rootPath);
        if (!fullPath.StartsWith(normalizedRoot, StringComparison.Ordinal))
            throw new InvalidOperationException("Ruta de almacenamiento fuera de RootPath");

        return fullPath;
    }
}
