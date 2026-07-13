using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Domain.Entities;

namespace OmniTask.Application.Services;

public class DeviceService : IDeviceService
{
    private readonly DbContext _db;
    private readonly DbSet<Device> _devices;

    public DeviceService(DbContext db)
    {
        _db = db;
        _devices = db.Set<Device>();
    }

    public async Task RegisterAsync(Guid userId, string fcmToken, string platform)
    {
        // Upsert por fcm_token, no por usuario (§8): si el mismo dispositivo se
        // reinstala o cambia de cuenta, el token se reasigna en vez de duplicarse.
        var device = await _devices.SingleOrDefaultAsync(d => d.FcmToken == fcmToken);
        if (device is null)
        {
            device = new Device { Id = Guid.NewGuid(), FcmToken = fcmToken };
            _devices.Add(device);
        }

        device.UserId = userId;
        device.Platform = Enum.Parse<DevicePlatform>(platform, ignoreCase: true);
        device.LastSeenAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
    }

    public async Task<List<DeviceResponse>> ListAsync(Guid userId) =>
        await _devices.Where(d => d.UserId == userId)
            .Select(d => new DeviceResponse(d.Id, d.FcmToken, d.Platform.ToString().ToLower(), d.LastSeenAt))
            .ToListAsync();

    public async Task DeleteAsync(Guid userId, Guid deviceId)
    {
        var device = await _devices.SingleOrDefaultAsync(d => d.Id == deviceId && d.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Dispositivo no encontrado");
        _devices.Remove(device);
        await _db.SaveChangesAsync();
    }
}
