using FirebaseAdmin.Messaging;
using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Domain.Entities;
using OmniTask.Infrastructure.Persistence;

namespace OmniTask.Infrastructure.BackgroundJobs;

// Reemplaza Celery Beat + Redis (§8) con jobs recurrentes de Hangfire sobre el
// mismo PostgreSQL — un motor de datos menos que operar en el servidor Windows.
public class ReminderDispatchJob
{
    private readonly OmniTaskDbContext _db;
    private readonly IPushSender _pushSender;
    private readonly IWhatsAppClient _whatsAppClient;

    public ReminderDispatchJob(OmniTaskDbContext db, IPushSender pushSender, IWhatsAppClient whatsAppClient)
    {
        _db = db;
        _pushSender = pushSender;
        _whatsAppClient = whatsAppClient;
    }

    // Recurrente cada minuto (Program.cs). El SELECT ... FOR UPDATE SKIP LOCKED
    // es lo que evita que dos ejecuciones solapadas envíen el mismo recordatorio
    // dos veces — idéntico al diseño original de Celery en la §8.
    public async Task DispatchDueRemindersAsync()
    {
        await using var transaction = await _db.Database.BeginTransactionAsync();

        var due = await _db.Reminders
            .FromSqlRaw(@"
                SELECT * FROM reminders
                WHERE remind_at <= now() AND status = 'pending'
                ORDER BY remind_at
                LIMIT 200
                FOR UPDATE SKIP LOCKED")
            .ToListAsync();

        foreach (var reminder in due)
            reminder.Status = ReminderStatus.Processing;

        await _db.SaveChangesAsync();
        await transaction.CommitAsync();

        foreach (var reminder in due)
            Hangfire.BackgroundJob.Enqueue<ReminderDispatchJob>(job => job.SendReminderAsync(reminder.Id));
    }

    public async Task SendReminderAsync(Guid reminderId)
    {
        var reminder = await _db.Reminders
            .Include(r => r.Activity).ThenInclude(a => a.User).ThenInclude(u => u.Devices)
            .Include(r => r.Activity).ThenInclude(a => a.Contact)
            .SingleAsync(r => r.Id == reminderId);

        var activity = reminder.Activity;

        try
        {
            if (reminder.Channel is ReminderChannel.Push or ReminderChannel.Both)
                await SendPushAsync(activity);

            if (reminder.Channel is ReminderChannel.Whatsapp or ReminderChannel.Both && activity.Contact is not null)
            {
                await _whatsAppClient.SendTemplateMessageAsync(
                    activity.Contact.PhoneE164,
                    "appointment_reminder",
                    "es_CO",
                    new[]
                    {
                        activity.Contact.FullName,
                        activity.StartsAt!.Value.ToString("d MMM"),
                        activity.StartsAt!.Value.ToString("h:mm tt"),
                    });
            }

            reminder.Status = ReminderStatus.Sent;
            reminder.SentAt = DateTimeOffset.UtcNow;
        }
        catch
        {
            reminder.Status = ReminderStatus.Failed;
            throw; // Hangfire reintenta según su política configurada (retries automáticos).
        }
        finally
        {
            await _db.SaveChangesAsync();
        }
    }

    private async Task SendPushAsync(Activity activity)
    {
        foreach (var device in activity.User.Devices.ToList())
        {
            try
            {
                await _pushSender.SendAsync(
                    device.FcmToken,
                    "Recordatorio",
                    $"{activity.Title} - {activity.StartsAt:HH:mm}",
                    new Dictionary<string, string> { ["activity_id"] = activity.Id.ToString(), ["type"] = "reminder" });
            }
            catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
            {
                _db.Devices.Remove(device);
            }
        }
    }
}
