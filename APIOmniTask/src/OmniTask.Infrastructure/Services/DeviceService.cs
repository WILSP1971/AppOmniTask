using Npgsql;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;

namespace OmniTask.Infrastructure.Services;

public class DeviceService : SqlServiceBase, IDeviceService
{
    public DeviceService(NpgsqlDataSource dataSource) : base(dataSource)
    {
    }

    public Task RegisterAsync(Guid userId, string fcmToken, string platform) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_upsert_device(@user_id, @fcm_token, @platform)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("fcm_token", fcmToken);
        cmd.Parameters.Add(new NpgsqlParameter("platform", EnumParsing.Parse<DevicePlatform>(platform, "platform")) { DataTypeName = "device_platform" });
        await cmd.ExecuteNonQueryAsync();
    });

    public Task<List<DeviceResponse>> ListAsync(Guid userId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_list_devices(@user_id)";
        cmd.Parameters.AddWithValue("user_id", userId);

        var items = new List<DeviceResponse>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            items.Add(new DeviceResponse(
                reader.GetGuid(reader.GetOrdinal("id")),
                reader.GetString(reader.GetOrdinal("fcm_token")),
                reader.GetFieldValue<DevicePlatform>(reader.GetOrdinal("platform")).ToString().ToLowerInvariant(),
                reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("last_seen_at"))));
        }
        return items;
    });

    public Task DeleteAsync(Guid userId, Guid deviceId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_delete_device(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", deviceId);
        await cmd.ExecuteNonQueryAsync();
    });
}
