using FirebaseAdmin.Messaging;
using Npgsql;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;

namespace OmniTask.Infrastructure.BackgroundJobs;

// Reemplaza Celery Beat + Redis (§8) con jobs recurrentes de Hangfire que
// invocan las funciones/procedimientos de db/03_stored_procedures_and_functions.sql
// — un motor de datos menos que operar en el servidor Windows.
public class ReminderDispatchJob
{
    private readonly NpgsqlDataSource _dataSource;
    private readonly IPushSender _pushSender;
    private readonly IWhatsAppClient _whatsAppClient;

    public ReminderDispatchJob(NpgsqlDataSource dataSource, IPushSender pushSender, IWhatsAppClient whatsAppClient)
    {
        _dataSource = dataSource;
        _pushSender = pushSender;
        _whatsAppClient = whatsAppClient;
    }

    // Recurrente cada minuto (Program.cs). fn_claim_due_reminders hace el
    // SELECT ... FOR UPDATE SKIP LOCKED + marcar processing en un solo
    // statement atómico — evita que dos ejecuciones solapadas envíen el
    // mismo recordatorio dos veces.
    public async Task DispatchDueRemindersAsync()
    {
        var reminderIds = new List<Guid>();

        await using (var conn = await _dataSource.OpenConnectionAsync())
        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT id FROM fn_claim_due_reminders(@limit)";
            cmd.Parameters.AddWithValue("limit", 200);

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                reminderIds.Add(reader.GetGuid(0));
        }

        foreach (var reminderId in reminderIds)
            Hangfire.BackgroundJob.Enqueue<ReminderDispatchJob>(job => job.SendReminderAsync(reminderId));
    }

    public async Task SendReminderAsync(Guid reminderId)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        Guid activityId, userId;
        Guid? contactId;
        string activityTitle, contactFullName = "", contactPhoneE164 = "";
        DateTimeOffset? activityStartsAt;
        ReminderChannel channel;

        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT * FROM fn_get_reminder_dispatch_info(@id)";
            cmd.Parameters.AddWithValue("id", reminderId);

            await using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();

            channel = reader.GetFieldValue<ReminderChannel>(reader.GetOrdinal("channel"));
            activityId = reader.GetGuid(reader.GetOrdinal("activity_id"));
            activityTitle = reader.GetString(reader.GetOrdinal("activity_title"));
            var startsAtOrdinal = reader.GetOrdinal("activity_starts_at");
            activityStartsAt = reader.IsDBNull(startsAtOrdinal) ? null : reader.GetFieldValue<DateTimeOffset>(startsAtOrdinal);
            userId = reader.GetGuid(reader.GetOrdinal("user_id"));

            var contactIdOrdinal = reader.GetOrdinal("contact_id");
            contactId = reader.IsDBNull(contactIdOrdinal) ? null : reader.GetGuid(contactIdOrdinal);
            if (contactId is not null)
            {
                contactFullName = reader.GetString(reader.GetOrdinal("contact_full_name"));
                contactPhoneE164 = reader.GetString(reader.GetOrdinal("contact_phone_e164"));
            }
        }

        try
        {
            if (channel is ReminderChannel.Push or ReminderChannel.Both)
                await SendPushAsync(conn, userId, activityId, activityTitle, activityStartsAt);

            if (channel is ReminderChannel.Whatsapp or ReminderChannel.Both && contactId is not null)
            {
                var wamid = await _whatsAppClient.SendTemplateMessageAsync(
                    contactPhoneE164,
                    "appointment_reminder",
                    "es_CO",
                    new[]
                    {
                        contactFullName,
                        activityStartsAt!.Value.ToString("d MMM"),
                        activityStartsAt!.Value.ToString("h:mm tt"),
                    });

                await LogNotificationAsync(
                    conn, reminderId, userId, NotificationChannel.Whatsapp, NotificationStatus.Sent,
                    $"Recordatorio de WhatsApp: {activityTitle}", wamid);
            }

            await using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = "CALL sp_mark_reminder_sent(@id)";
                cmd.Parameters.AddWithValue("id", reminderId);
                await cmd.ExecuteNonQueryAsync();
            }
        }
        catch
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "CALL sp_mark_reminder_failed(@id)";
            cmd.Parameters.AddWithValue("id", reminderId);
            await cmd.ExecuteNonQueryAsync();
            throw; // Hangfire reintenta según su política configurada (retries automáticos).
        }
    }

    private async Task SendPushAsync(
        NpgsqlConnection conn, Guid userId, Guid activityId, string activityTitle, DateTimeOffset? startsAt)
    {
        var devices = new List<(Guid Id, string FcmToken)>();

        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT id, fcm_token FROM fn_list_devices(@user_id)";
            cmd.Parameters.AddWithValue("user_id", userId);
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                devices.Add((reader.GetGuid(0), reader.GetString(1)));
        }

        foreach (var device in devices)
        {
            try
            {
                await _pushSender.SendAsync(
                    device.FcmToken,
                    "Recordatorio",
                    $"{activityTitle} - {startsAt:HH:mm}",
                    new Dictionary<string, string> { ["activity_id"] = activityId.ToString(), ["type"] = "reminder" });

                await LogNotificationAsync(
                    conn, null, userId, NotificationChannel.Push, NotificationStatus.Sent,
                    $"Recordatorio: {activityTitle}", null);
            }
            catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "CALL sp_delete_device_by_id(@id)";
                cmd.Parameters.AddWithValue("id", device.Id);
                await cmd.ExecuteNonQueryAsync();
            }
        }
    }

    private static async Task LogNotificationAsync(
        NpgsqlConnection conn, Guid? reminderId, Guid userId, NotificationChannel channel,
        NotificationStatus status, string summary, string? providerMessageId)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT fn_log_notification(@reminder_id, @user_id, @channel, @status, @summary, @provider_message_id)";
        cmd.Parameters.AddWithValue("reminder_id", (object?)reminderId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("channel", channel);
        cmd.Parameters.AddWithValue("status", status);
        cmd.Parameters.AddWithValue("summary", summary);
        cmd.Parameters.AddWithValue("provider_message_id", (object?)providerMessageId ?? DBNull.Value);
        await cmd.ExecuteScalarAsync();
    }
}
