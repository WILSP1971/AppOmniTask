using Npgsql;
using OmniTask.Application.Interfaces;

namespace OmniTask.Infrastructure.BackgroundJobs;

// Recurrente diario, 8:00 a.m. (Program.cs) — resumen de actividades sin fecha
// agrupadas por usuario (Fase 5, §4), vía fn_unscheduled_digest_counts.
public class UnscheduledDigestJob
{
    private readonly NpgsqlDataSource _dataSource;
    private readonly IPushSender _pushSender;

    public UnscheduledDigestJob(NpgsqlDataSource dataSource, IPushSender pushSender)
    {
        _dataSource = dataSource;
        _pushSender = pushSender;
    }

    public async Task RunAsync()
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        var counts = new List<(Guid UserId, long Count)>();
        await using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT * FROM fn_unscheduled_digest_counts()";
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                counts.Add((reader.GetGuid(0), reader.GetInt64(1)));
        }

        foreach (var (userId, count) in counts)
        {
            var devices = new List<string>();
            await using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = "SELECT fcm_token FROM fn_list_devices(@user_id)";
                cmd.Parameters.AddWithValue("user_id", userId);
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                    devices.Add(reader.GetString(0));
            }

            foreach (var fcmToken in devices)
            {
                await _pushSender.SendAsync(
                    fcmToken,
                    "Pendientes por programar",
                    $"Tienes {count} actividad(es) sin programar",
                    new Dictionary<string, string> { ["type"] = "digest" });
            }
        }
    }
}
