using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api.Controllers;

[ApiController]
[Route("api/v1/activities")]
[Authorize]
public class ActivitiesController : ControllerBase
{
    private readonly IActivityService _activityService;

    public ActivitiesController(IActivityService activityService) => _activityService = activityService;

    [HttpPost]
    public async Task<IActionResult> Create(ActivityCreateRequest request)
    {
        var activity = await _activityService.CreateAsync(User.GetUserId(), request);
        return CreatedAtAction(nameof(GetById), new { id = activity.Id }, activity);
    }

    [HttpGet]
    public async Task<ActionResult<PagedResponse<ActivityResponse>>> List(
        [FromQuery] DateTimeOffset? from,
        [FromQuery] DateTimeOffset? to,
        [FromQuery] string? type,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int limit = 50) =>
        Ok(await _activityService.ListAsync(User.GetUserId(), from, to, type, status, page, limit));

    // Atajo equivalente a status=unscheduled sin rango de fecha (§6) — alimenta
    // la bandeja de pendientes por programar de la §12.
    [HttpGet("unscheduled")]
    public async Task<ActionResult<List<ActivityResponse>>> ListUnscheduled() =>
        Ok(await _activityService.ListUnscheduledAsync(User.GetUserId()));

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ActivityResponse>> GetById(Guid id) =>
        Ok(await _activityService.GetByIdAsync(User.GetUserId(), id));

    [HttpPatch("{id:guid}")]
    public async Task<ActionResult<ActivityResponse>> Update(Guid id, ActivityUpdateRequest request) =>
        Ok(await _activityService.UpdateAsync(User.GetUserId(), id, request));

    // Soft delete (§6): status = cancelled, nunca borrado físico.
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        await _activityService.CancelAsync(User.GetUserId(), id);
        return NoContent();
    }
}
