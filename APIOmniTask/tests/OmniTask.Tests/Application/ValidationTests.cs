using OmniTask.Application;
using Xunit;

namespace OmniTask.Tests.Application;

// Pruebas unitarias puras (sin BD) de AttachmentValidation (SPEC-002 §3 RF7)
// y MeetingValidation (SPEC-003 §3 RF2, §5) — corren siempre, sin depender de
// Postgres. Cubren la lógica de validación de servidor que se ejercita
// también, de forma integrada, en AttachmentServiceTests y en
// ActivityServiceMeetingTests.
public class AttachmentValidationTests
{
    [Theory]
    [InlineData("image/jpeg")]
    [InlineData("image/png")]
    [InlineData("image/heic")]
    [InlineData("application/pdf")]
    public void IsContentTypeAllowed_acepta_los_tipos_de_la_lista_blanca(string contentType) =>
        Assert.True(AttachmentValidation.IsContentTypeAllowed(contentType));

    [Theory]
    [InlineData("application/x-msdownload")] // .exe
    [InlineData("application/vnd.openxmlformats-officedocument.wordprocessingml.document")] // .docx
    [InlineData("text/html")]
    [InlineData(null)]
    public void IsContentTypeAllowed_rechaza_tipos_fuera_de_la_lista_blanca(string? contentType) =>
        Assert.False(AttachmentValidation.IsContentTypeAllowed(contentType));

    [Theory]
    [InlineData("image/jpeg", "foto.jpg")]
    [InlineData("image/jpeg", "foto.jpeg")]
    [InlineData("image/png", "captura.PNG")] // insensible a mayúsculas
    [InlineData("image/heic", "imagen.heic")]
    [InlineData("application/pdf", "informe.pdf")]
    public void IsExtensionCoherent_acepta_extension_que_coincide_con_el_content_type(string contentType, string fileName) =>
        Assert.True(AttachmentValidation.IsExtensionCoherent(contentType, fileName));

    [Theory]
    [InlineData("application/pdf", "documento.docx")]
    [InlineData("image/png", "imagen.exe")]
    [InlineData("image/jpeg", "sin_extension")]
    [InlineData("application/x-msdownload", "virus.exe")] // content-type ya no permitido
    public void IsExtensionCoherent_rechaza_extension_incoherente_o_tipo_no_permitido(string contentType, string fileName) =>
        Assert.False(AttachmentValidation.IsExtensionCoherent(contentType, fileName));

    [Fact]
    public void MaxSizeBytes_es_10_megabytes_exactos() =>
        Assert.Equal(10L * 1024 * 1024, AttachmentValidation.MaxSizeBytes);
}

public class MeetingValidationTests
{
    [Theory]
    [InlineData("https://meet.google.com/abc-defg-hij")]
    [InlineData("http://teams.microsoft.com/l/meetup-join/xyz")]
    [InlineData("https://example.com")]
    public void IsValidMeetingUrl_acepta_esquemas_http_y_https(string url) =>
        Assert.True(MeetingValidation.IsValidMeetingUrl(url));

    [Theory]
    [InlineData("ftp://example.com/reunion")]
    [InlineData("no-es-una-url")]
    [InlineData("javascript:alert(1)")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("   ")]
    public void IsValidMeetingUrl_rechaza_esquemas_no_http_o_texto_invalido(string? url) =>
        Assert.False(MeetingValidation.IsValidMeetingUrl(url));

    [Theory]
    [InlineData("meet")]
    [InlineData("teams")]
    [InlineData("other")]
    [InlineData("MEET")] // insensible a mayúsculas
    public void IsValidProvider_acepta_el_conjunto_permitido(string provider) =>
        Assert.True(MeetingValidation.IsValidProvider(provider));

    [Theory]
    [InlineData("zoom")]
    [InlineData("")]
    [InlineData(null)]
    public void IsValidProvider_rechaza_proveedores_fuera_del_conjunto_permitido(string? provider) =>
        Assert.False(MeetingValidation.IsValidProvider(provider));
}
