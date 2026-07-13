using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api.Controllers;

[ApiController]
[Route("api/v1/notifications")]
[Authorize]
public class NotificationsController : ControllerBase
{
    private readonly INotificationService _notificationService;

    public NotificationsController(INotificationService notificationService) =>
        _notificationService = notificationService;

    [HttpGet]
    public async Task<ActionResult<PagedResponse<NotificationResponse>>> List(
        [FromQuery] bool unreadOnly = false, [FromQuery] int page = 1, [FromQuery] int limit = 20) =>
        Ok(await _notificationService.ListAsync(User.GetUserId(), unreadOnly, page, limit));

    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount() =>
        Ok(new { count = await _notificationService.UnreadCountAsync(User.GetUserId()) });

    [HttpPatch("{id:guid}/ack")]
    public async Task<IActionResult> Acknowledge(Guid id)
    {
        await _notificationService.AcknowledgeAsync(User.GetUserId(), id);
        return NoContent();
    }

    [HttpPost("ack-all")]
    public async Task<IActionResult> AcknowledgeAll()
    {
        await _notificationService.AcknowledgeAllAsync(User.GetUserId());
        return NoContent();
    }
}
