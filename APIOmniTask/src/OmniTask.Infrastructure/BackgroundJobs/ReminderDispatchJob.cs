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

    // SPEC-008 (RF7/RF11): fn_get_reminder_dispatch_info ahora es SETOF, una
    // fila por contacto de la actividad (LEFT JOIN); una actividad sin
    // contactos devuelve una única fila con contact_* en NULL. Se representa
    // aquí como un registro liviano por fila para poder recorrerlas todas.
    private sealed record DispatchRow(
        ReminderChannel Channel, Guid ActivityId, string ActivityTitle, DateTimeOffset? ActivityStartsAt,
        Guid UserId, Guid? ContactId, string? ContactFullName, string? ContactPhoneE164);

    public async Task SendReminderAsync(Guid reminderId)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        var rows = new List<DispatchRow>();

        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT * FROM fn_get_reminder_dispatch_info(@id)";
            cmd.Parameters.AddWithValue("id", reminderId);

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var contactIdOrdinal = reader.GetOrdinal("contact_id");
                var contactId = reader.IsDBNull(contactIdOrdinal) ? (Guid?)null : reader.GetGuid(contactIdOrdinal);

                var startsAtOrdinal = reader.GetOrdinal("activity_starts_at");

                rows.Add(new DispatchRow(
                    reader.GetFieldValue<ReminderChannel>(reader.GetOrdinal("channel")),
                    reader.GetGuid(reader.GetOrdinal("activity_id")),
                    reader.GetString(reader.GetOrdinal("activity_title")),
                    reader.IsDBNull(startsAtOrdinal) ? null : reader.GetFieldValue<DateTimeOffset>(startsAtOrdinal),
                    reader.GetGuid(reader.GetOrdinal("user_id")),
                    contactId,
                    contactId is null ? null : reader.GetString(reader.GetOrdinal("contact_full_name")),
                    contactId is null ? null : reader.GetString(reader.GetOrdinal("contact_phone_e164"))));
            }
        }

        // Datos comunes a todas las filas (misma actividad/reminder): se toman
        // de la primera fila, que siempre existe (LEFT JOIN nunca da 0 filas).
        var first = rows[0];

        try
        {
            // El push al dueño se envía una sola vez por reminder (RNF5), no
            // una por contacto — se ejecuta fuera del bucle de contactos.
            if (first.Channel is ReminderChannel.Push or ReminderChannel.Both)
                await SendPushAsync(conn, first.UserId, first.ActivityId, first.ActivityTitle, first.ActivityStartsAt);

            // RF11: corrige el bug de precedencia de la condición original
            // (`channel is ReminderChannel.Whatsapp or ReminderChannel.Both &&
            // contactId is not null`) — `&&` liga más fuerte que `or`, así que
            // Postgres/C# evaluaba `Whatsapp OR (Both && contactId is not
            // null)`, lo que enviaba WhatsApp igual sin contacto cuando el
            // canal era `Whatsapp`. Con paréntesis explícitos alrededor de la
            // disyunción de canal, la condición evalúa lo esperado: "el canal
            // incluye WhatsApp Y hay un contacto para esta fila".
            if ((first.Channel is ReminderChannel.Whatsapp or ReminderChannel.Both))
            {
                foreach (var row in rows)
                {
                    if (row.ContactId is null || string.IsNullOrWhiteSpace(row.ContactPhoneE164))
                        continue;

                    try
                    {
                        var wamid = await _whatsAppClient.SendTemplateMessageAsync(
                            row.ContactPhoneE164,
                            "appointment_reminder",
                            "es_CO",
                            new[]
                            {
                                row.ContactFullName ?? string.Empty,
                                row.ActivityStartsAt!.Value.ToString("d MMM"),
                                row.ActivityStartsAt!.Value.ToString("h:mm tt"),
                            });

                        await LogNotificationAsync(
                            conn, reminderId, first.UserId, NotificationChannel.Whatsapp, NotificationStatus.Sent,
                            $"Recordatorio de WhatsApp: {first.ActivityTitle}", wamid);
                    }
                    catch (Exception)
                    {
                        // Un destinatario inválido no debe impedir el envío a
                        // los demás contactos de la misma actividad (RF11,
                        // §5): se registra su notification_log como fallido y
                        // se continúa el bucle, sin relanzar — el reminder
                        // solo se marca failed por una excepción que amerite
                        // reintento de Hangfire (fuera de este bucle).
                        await LogNotificationAsync(
                            conn, reminderId, first.UserId, NotificationChannel.Whatsapp, NotificationStatus.Failed,
                            $"Recordatorio de WhatsApp: {first.ActivityTitle}", null);
                    }
                }
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
