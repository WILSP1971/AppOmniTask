using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Infrastructure.Persistence;

namespace OmniTask.Infrastructure.BackgroundJobs;

// Recurrente diario, 8:00 a.m. (Program.cs) — resumen de actividades sin fecha
// agrupadas por usuario (Fase 5, §4).
public class UnscheduledDigestJob
{
    private readonly OmniTaskDbContext _db;
    private readonly IPushSender _pushSender;

    public UnscheduledDigestJob(OmniTaskDbContext db, IPushSender pushSender)
    {
        _db = db;
        _pushSender = pushSender;
    }

    public async Task RunAsync()
    {
        var counts = await _db.Activities
            .Where(a => a.StartsAt == null && a.Status == ActivityStatus.Unscheduled)
            .GroupBy(a => a.UserId)
            .Select(g => new { UserId = g.Key, Count = g.Count() })
            .ToListAsync();

        foreach (var entry in counts)
        {
            var devices = await _db.Devices.Where(d => d.UserId == entry.UserId).ToListAsync();
            foreach (var device in devices)
            {
                await _pushSender.SendAsync(
                    device.FcmToken,
                    "Pendientes por programar",
                    $"Tienes {entry.Count} actividad(es) sin programar",
                    new Dictionary<string, string> { ["type"] = "digest" });
            }
        }
    }
}
