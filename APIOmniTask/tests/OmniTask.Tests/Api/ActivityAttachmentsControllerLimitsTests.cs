using System.Reflection;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Api.Controllers;
using Xunit;

namespace OmniTask.Tests.Api;

// Verificación estática (sin Postgres, sin servidor HTTP real) del caso
// límite señalado por WOLVERINE: que el endpoint de subida realmente declara
// un límite de tamaño de request ACOTADO a esta ruta (RNF2), para que Kestrel
// corte con 4xx antes de que un archivo enorme llegue al controlador — en vez
// de depender solo del chequeo interno de AttachmentService (10 MB), que ya
// se prueba en AttachmentServiceTests.
//
// Limitación explícita: este test NO levanta un servidor Kestrel real ni
// envía un multipart de >11 MB por HTTP (este entorno no tiene
// WebApplicationFactory/TestServer configurado en el proyecto — no es un
// patrón ya usado aquí, ver nota en el reporte de HAWKEYE). Lo que sí
// confirma con certeza: que [RequestSizeLimit] y [RequestFormLimits] están
// presentes en el método Upload con el mismo valor (11 MB) que usa el
// controlador para su propio chequeo de 413, así que un archivo que supere
// ese límite es cortado por el middleware de ASP.NET Core (que dispara
// BadHttpRequestException / 413 antes de invocar el action) y no por una
// excepción sin capturar.
public class ActivityAttachmentsControllerLimitsTests
{
    private static MethodInfo GetUploadMethod() =>
        typeof(ActivityAttachmentsController).GetMethod(nameof(ActivityAttachmentsController.Upload))
        ?? throw new InvalidOperationException("No se encontró ActivityAttachmentsController.Upload");

    [Fact]
    public void Upload_declara_RequestSizeLimit_de_11MB()
    {
        var attribute = GetUploadMethod().GetCustomAttribute<RequestSizeLimitAttribute>();

        Assert.NotNull(attribute);
        // MaxRequestBodySize es una implementación explícita de
        // IRequestSizeLimitMetadata (no una propiedad pública directa del
        // atributo) — así es como Kestrel/ASP.NET Core la lee en runtime.
        var metadata = (IRequestSizeLimitMetadata)attribute!;
        Assert.Equal(11 * 1024 * 1024, metadata.MaxRequestBodySize);
    }

    [Fact]
    public void Upload_declara_RequestFormLimits_con_el_mismo_limite_de_multipart()
    {
        var attribute = GetUploadMethod().GetCustomAttribute<RequestFormLimitsAttribute>();

        Assert.NotNull(attribute);
        Assert.Equal(11 * 1024 * 1024, attribute!.MultipartBodyLengthLimit);
    }
}
