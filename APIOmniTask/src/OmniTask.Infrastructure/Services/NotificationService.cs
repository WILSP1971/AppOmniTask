using Npgsql;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;

namespace OmniTask.Infrastructure.Services;

public class NotificationService : SqlServiceBase, INotificationService
{
    public NotificationService(NpgsqlDataSource dataSource) : base(dataSource)
    {
    }

    public Task<PagedResponse<NotificationResponse>> ListAsync(Guid userId, bool unreadOnly, int page, int limit) =>
        RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_list_notifications(@user_id, @unread_only, @page, @limit)";
            cmd.Parameters.AddWithValue("user_id", userId);
            cmd.Parameters.AddWithValue("unread_only", unreadOnly);
            cmd.Parameters.AddWithValue("page", page);
            cmd.Parameters.AddWithValue("limit", limit);

            var items = new List<NotificationResponse>();
            long total = 0;

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var activityIdOrdinal = reader.GetOrdinal("activity_id");
                items.Add(new NotificationResponse(
                    reader.GetGuid(reader.GetOrdinal("id")),
                    reader.GetFieldValue<NotificationChannel>(reader.GetOrdinal("channel")).ToString().ToLowerInvariant(),
                    reader.GetFieldValue<NotificationStatus>(reader.GetOrdinal("status")).ToString().ToLowerInvariant(),
                    reader.GetString(reader.GetOrdinal("summary")),
                    reader.IsDBNull(activityIdOrdinal) ? null : reader.GetGuid(activityIdOrdinal),
                    reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("created_at")),
                    reader.IsDBNull(reader.GetOrdinal("acknowledged_at"))
                        ? null
                        : reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("acknowledged_at"))));
                total = reader.GetInt64(reader.GetOrdinal("total_count"));
            }

            return new PagedResponse<NotificationResponse>(items, page, limit, (int)total);
        });

    public Task<int> UnreadCountAsync(Guid userId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT fn_unread_notification_count(@user_id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        var count = (long)(await cmd.ExecuteScalarAsync())!;
        return (int)count;
    });

    public Task AcknowledgeAsync(Guid userId, Guid notificationId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_acknowledge_notification(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", notificationId);
        await cmd.ExecuteNonQueryAsync();
    });

    public Task AcknowledgeAllAsync(Guid userId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_acknowledge_all_notifications(@user_id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        await cmd.ExecuteNonQueryAsync();
    });

    public Task ClearAllAsync(Guid userId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_clear_notifications(@user_id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        await cmd.ExecuteNonQueryAsync();
    });
}
