using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api.Controllers;

// SPEC-002 (§3): adjuntos de una actividad. Controlador delgado — toda la
// validación de negocio y persistencia vive en IAttachmentService
// (Infrastructure). Autorización por dueño: IAttachmentService responde 404
// si la actividad no existe o pertenece a otro usuario (RNF1), nunca revela
// la existencia del recurso ajeno.
[ApiController]
[Route("api/v1/activities/{activityId:guid}/attachments")]
[Authorize]
public class ActivityAttachmentsController : ControllerBase
{
    // RNF2: límite de request acotado a esta ruta (10 MB + margen para el
    // resto del multipart), sin tocar los límites globales de Kestrel/Program.
    private const long MaxRequestBodyBytes = 11 * 1024 * 1024;

    private readonly IAttachmentService _attachmentService;

    public ActivityAttachmentsController(IAttachmentService attachmentService) =>
        _attachmentService = attachmentService;

    [HttpPost]
    [RequestSizeLimit(MaxRequestBodyBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = MaxRequestBodyBytes)]
    public async Task<IActionResult> Upload(Guid activityId, IFormFile? file)
    {
        if (file is null || file.Length == 0)
            throw new ApiException(400, "missing_file", "Falta el campo 'file' o el multipart es inválido");

        if (file.Length > OmniTask.Application.AttachmentValidation.MaxSizeBytes)
            throw new ApiException(413, "payload_too_large", "El archivo supera el tamaño máximo permitido (10 MB)");

        await using var stream = file.OpenReadStream();
        var attachment = await _attachmentService.UploadAsync(
            User.GetUserId(), activityId, file.FileName, file.ContentType, stream);

        return CreatedAtAction(nameof(Download), new { activityId, attachmentId = attachment.Id }, attachment);
    }

    [HttpGet]
    public async Task<ActionResult<List<AttachmentResponse>>> List(Guid activityId) =>
        Ok(await _attachmentService.ListAsync(User.GetUserId(), activityId));

    [HttpGet("{attachmentId:guid}")]
    public async Task<IActionResult> Download(Guid activityId, Guid attachmentId)
    {
        var (metadata, content) = await _attachmentService.DownloadAsync(User.GetUserId(), activityId, attachmentId);
        return File(content, metadata.ContentType, metadata.FileName);
    }

    [HttpDelete("{attachmentId:guid}")]
    public async Task<IActionResult> Delete(Guid activityId, Guid attachmentId)
    {
        await _attachmentService.DeleteAsync(User.GetUserId(), activityId, attachmentId);
        return NoContent();
    }
}
