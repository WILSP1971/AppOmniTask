using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain.Entities;

namespace OmniTask.Application.Services;

public class NotificationService : INotificationService
{
    private readonly DbContext _db;
    private readonly DbSet<NotificationLog> _notifications;

    public NotificationService(DbContext db)
    {
        _db = db;
        _notifications = db.Set<NotificationLog>();
    }

    public async Task<PagedResponse<NotificationResponse>> ListAsync(Guid userId, bool unreadOnly, int page, int limit)
    {
        var query = _notifications.Where(n => n.UserId == userId);
        if (unreadOnly) query = query.Where(n => n.AcknowledgedAt == null);
        query = query.OrderByDescending(n => n.CreatedAt);

        var total = await query.CountAsync();
        var items = await query.Skip((page - 1) * limit).Take(limit)
            .Select(n => new NotificationResponse(
                n.Id, n.Channel.ToString().ToLower(), n.Status.ToString().ToLower(), n.Summary,
                n.Reminder != null ? n.Reminder.ActivityId : (Guid?)null, n.CreatedAt, n.AcknowledgedAt))
            .ToListAsync();

        return new PagedResponse<NotificationResponse>(items, page, limit, total);
    }

    // Endpoint propio y liviano (§17): alimenta el badge de la campana sin
    // traer el listado completo solo para contar cuántos faltan por leer.
    public async Task<int> UnreadCountAsync(Guid userId) =>
        await _notifications.CountAsync(n => n.UserId == userId && n.AcknowledgedAt == null);

    public async Task AcknowledgeAsync(Guid userId, Guid notificationId)
    {
        var notification = await _notifications.SingleOrDefaultAsync(n => n.Id == notificationId && n.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Notificación no encontrada");
        notification.AcknowledgedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
    }

    public Task AcknowledgeAllAsync(Guid userId) =>
        _notifications.Where(n => n.UserId == userId && n.AcknowledgedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(n => n.AcknowledgedAt, DateTimeOffset.UtcNow));
}
