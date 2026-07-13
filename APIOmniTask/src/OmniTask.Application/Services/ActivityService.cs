using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Domain.Entities;

namespace OmniTask.Application.Services;

public class ActivityService : IActivityService
{
    private readonly DbContext _db;
    private readonly DbSet<Activity> _activities;
    private readonly DbSet<User> _users;

    public ActivityService(DbContext db)
    {
        _db = db;
        _activities = db.Set<Activity>();
        _users = db.Set<User>();
    }

    public async Task<ActivityResponse> CreateAsync(Guid userId, ActivityCreateRequest request)
    {
        if (request.EndsAt is not null && request.StartsAt is not null && request.EndsAt <= request.StartsAt)
            throw new ApiException(422, "invalid_range", "ends_at debe ser posterior a starts_at");

        var user = await _users.FindAsync(userId)
            ?? throw new ApiException(404, "not_found", "Usuario no encontrado");

        var activity = new Activity
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            ContactId = request.ContactId,
            Type = Enum.Parse<ActivityType>(request.Type, ignoreCase: true),
            Title = request.Title,
            Description = request.Description,
            // NULL en starts_at fuerza unscheduled sin importar lo que envíe el cliente (§6).
            Status = request.StartsAt is null ? ActivityStatus.Unscheduled : ActivityStatus.Scheduled,
            StartsAt = request.StartsAt,
            EndsAt = request.EndsAt,
            Timezone = user.Timezone,
            Location = request.Location,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        if (activity.StartsAt is not null)
            GenerateReminders(activity, user.NotificationPreferences);

        _activities.Add(activity);
        await _db.SaveChangesAsync();
        return ToResponse(activity);
    }

    public async Task<PagedResponse<ActivityResponse>> ListAsync(
        Guid userId, DateTimeOffset? from, DateTimeOffset? to, string? type, string? status, int page, int limit)
    {
        var query = _activities.Where(a => a.UserId == userId);

        if (from is not null) query = query.Where(a => a.StartsAt >= from);
        if (to is not null) query = query.Where(a => a.StartsAt <= to);
        if (type is not null) query = query.Where(a => a.Type == Enum.Parse<ActivityType>(type, true));
        if (status is not null) query = query.Where(a => a.Status == Enum.Parse<ActivityStatus>(status, true));

        query = query.OrderBy(a => a.StartsAt);

        var total = await query.CountAsync();
        var items = await query.Skip((page - 1) * limit).Take(limit).ToListAsync();

        return new PagedResponse<ActivityResponse>(items.Select(ToResponse).ToList(), page, limit, total);
    }

    public async Task<List<ActivityResponse>> ListUnscheduledAsync(Guid userId) =>
        await _activities
            .Where(a => a.UserId == userId && a.StartsAt == null)
            .OrderByDescending(a => a.CreatedAt)
            .Select(a => ToResponse(a))
            .ToListAsync();

    public async Task<ActivityResponse> GetByIdAsync(Guid userId, Guid activityId)
    {
        var activity = await _activities.Include(a => a.Reminders)
            .SingleOrDefaultAsync(a => a.Id == activityId && a.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Actividad no encontrada");
        return ToResponse(activity, includeReminders: true);
    }

    public async Task<ActivityResponse> UpdateAsync(Guid userId, Guid activityId, ActivityUpdateRequest request)
    {
        var activity = await _activities.Include(a => a.Reminders)
            .SingleOrDefaultAsync(a => a.Id == activityId && a.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Actividad no encontrada");

        var reschedule = request.StartsAt is not null && request.StartsAt != activity.StartsAt;

        if (request.Title is not null) activity.Title = request.Title;
        if (request.Description is not null) activity.Description = request.Description;
        if (request.Location is not null) activity.Location = request.Location;
        if (request.StartsAt is not null) activity.StartsAt = request.StartsAt;
        if (request.EndsAt is not null) activity.EndsAt = request.EndsAt;
        if (request.Status is not null) activity.Status = Enum.Parse<ActivityStatus>(request.Status, true);

        var closing = activity.Status is ActivityStatus.Completed or ActivityStatus.Cancelled;

        if (reschedule || closing)
        {
            // Reprogramar o cerrar cancela los reminders pendientes sin enviarlos (§6).
            foreach (var reminder in activity.Reminders.Where(r => r.Status == ReminderStatus.Pending))
                reminder.Status = ReminderStatus.Failed;

            if (reschedule && !closing)
            {
                var user = await _users.FindAsync(userId);
                GenerateReminders(activity, user!.NotificationPreferences);
            }
        }

        activity.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return ToResponse(activity);
    }

    public Task CancelAsync(Guid userId, Guid activityId) =>
        // Soft delete: mismo contrato que DELETE /activities/{id} en la §6.
        UpdateAsync(userId, activityId, new ActivityUpdateRequest(null, null, null, null, "cancelled", null));

    private static void GenerateReminders(Activity activity, NotificationPreferences preferences)
    {
        foreach (var minutes in preferences.ReminderOffsetsMinutes)
        {
            activity.Reminders.Add(new Reminder
            {
                Id = Guid.NewGuid(),
                ActivityId = activity.Id,
                RemindAt = activity.StartsAt!.Value.AddMinutes(-minutes),
                Channel = Enum.Parse<ReminderChannel>(preferences.DefaultChannel, true),
                Status = ReminderStatus.Pending,
            });
        }
    }

    private static ActivityResponse ToResponse(Activity a, bool includeReminders = false) => new(
        a.Id, a.UserId, a.ContactId, a.Type.ToString().ToLowerInvariant(), a.Title, a.Description,
        a.Status.ToString().ToLowerInvariant(), a.StartsAt, a.EndsAt, a.Timezone, a.Location,
        a.CreatedAt, a.UpdatedAt,
        includeReminders
            ? a.Reminders.Select(r => new ReminderSummaryResponse(
                r.Id, r.RemindAt, r.Channel.ToString().ToLowerInvariant(), r.Status.ToString().ToLowerInvariant())).ToList()
            : null);
}
