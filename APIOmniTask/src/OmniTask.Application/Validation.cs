namespace OmniTask.Application;

// Validaciones de servidor compartidas entre servicios (defensa en
// profundidad: el cliente Flutter valida lo mismo, pero nunca se confía solo
// en él). Centralizadas aquí para que Api/Infrastructure no dupliquen las
// mismas listas de valores permitidos.

// SPEC-002 (§3 RF7, §4 RNF1): tipos permitidos y tamaño máximo de adjunto.
public static class AttachmentValidation
{
    public const long MaxSizeBytes = 10 * 1024 * 1024; // 10 MB

    public static readonly IReadOnlyDictionary<string, string[]> AllowedContentTypesToExtensions =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["image/jpeg"] = new[] { ".jpg", ".jpeg" },
            ["image/png"] = new[] { ".png" },
            ["image/heic"] = new[] { ".heic" },
            ["application/pdf"] = new[] { ".pdf" },
        };

    public static bool IsContentTypeAllowed(string? contentType) =>
        contentType is not null && AllowedContentTypesToExtensions.ContainsKey(contentType);

    public static bool IsExtensionCoherent(string? contentType, string fileName)
    {
        if (contentType is null || !AllowedContentTypesToExtensions.TryGetValue(contentType, out var extensions))
            return false;

        var extension = Path.GetExtension(fileName);
        return extension.Length > 0 && extensions.Contains(extension, StringComparer.OrdinalIgnoreCase);
    }
}

// SPEC-003 (§3 RF2, §5): esquema http/https válido y proveedor en el
// conjunto permitido.
public static class MeetingValidation
{
    public static readonly string[] AllowedProviders = { "meet", "teams", "other" };

    public static bool IsValidMeetingUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        return Uri.TryCreate(url, UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);
    }

    public static bool IsValidProvider(string? provider) =>
        provider is not null && AllowedProviders.Contains(provider, StringComparer.OrdinalIgnoreCase);
}
