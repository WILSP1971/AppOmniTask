using Npgsql;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;

namespace OmniTask.Infrastructure.Services;

public class ActivityService : SqlServiceBase, IActivityService
{
    public ActivityService(NpgsqlDataSource dataSource) : base(dataSource)
    {
    }

    public Task<ActivityResponse> CreateAsync(Guid userId, ActivityCreateRequest request) => RunAsync(async conn =>
    {
        ValidateMeeting(request.MeetingUrl, request.MeetingProvider);

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_create_activity(@user_id, @contact_id, @type, @title, @description, @starts_at, @ends_at, @location, @meeting_url, @meeting_provider)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("contact_id", (object?)request.ContactId ?? DBNull.Value);
        cmd.Parameters.Add(EnumParam("type", "activity_type", EnumParsing.Parse<ActivityType>(request.Type, "type")));
        cmd.Parameters.AddWithValue("title", request.Title);
        cmd.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
        cmd.Parameters.AddWithValue("starts_at", (object?)request.StartsAt ?? DBNull.Value);
        cmd.Parameters.AddWithValue("ends_at", (object?)request.EndsAt ?? DBNull.Value);
        cmd.Parameters.AddWithValue("location", (object?)request.Location ?? DBNull.Value);
        cmd.Parameters.AddWithValue("meeting_url", (object?)request.MeetingUrl ?? DBNull.Value);
        cmd.Parameters.AddWithValue("meeting_provider", (object?)request.MeetingProvider ?? DBNull.Value);

        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return MapActivity(reader);
    });

    public Task<PagedResponse<ActivityResponse>> ListAsync(
        Guid userId, DateTimeOffset? from, DateTimeOffset? to, string? type, string? status, int page, int limit) =>
        RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_list_activities(@user_id, @from, @to, @type, @status, @page, @limit)";
            cmd.Parameters.AddWithValue("user_id", userId);
            cmd.Parameters.AddWithValue("from", (object?)from ?? DBNull.Value);
            cmd.Parameters.AddWithValue("to", (object?)to ?? DBNull.Value);
            cmd.Parameters.Add(EnumParam("type", "activity_type", type is null ? null : EnumParsing.Parse<ActivityType>(type, "type")));
            cmd.Parameters.Add(EnumParam("status", "activity_status", status is null ? null : EnumParsing.Parse<ActivityStatus>(status, "status")));
            cmd.Parameters.AddWithValue("page", page);
            cmd.Parameters.AddWithValue("limit", limit);

            var items = new List<ActivityResponse>();
            long total = 0;

            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                items.Add(MapActivity(reader));
                total = reader.GetInt64(reader.GetOrdinal("total_count"));
            }

            return new PagedResponse<ActivityResponse>(items, page, limit, (int)total);
        });

    public Task<List<ActivityResponse>> ListUnscheduledAsync(Guid userId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_list_unscheduled_activities(@user_id)";
        cmd.Parameters.AddWithValue("user_id", userId);

        var items = new List<ActivityResponse>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync()) items.Add(MapActivity(reader));
        return items;
    });

    public Task<ActivityResponse> GetByIdAsync(Guid userId, Guid activityId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_get_activity_by_id(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", activityId);

        ActivityResponse activity;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync())
                throw new ApiException(404, "not_found", "Actividad no encontrada");
            activity = MapActivity(reader);
        }

        await using var remindersCmd = conn.CreateCommand();
        remindersCmd.CommandText = "SELECT * FROM fn_list_reminders_for_activity(@activity_id)";
        remindersCmd.Parameters.AddWithValue("activity_id", activityId);

        var reminders = new List<ReminderSummaryResponse>();
        await using var remindersReader = await remindersCmd.ExecuteReaderAsync();
        while (await remindersReader.ReadAsync())
        {
            reminders.Add(new ReminderSummaryResponse(
                remindersReader.GetGuid(remindersReader.GetOrdinal("id")),
                remindersReader.GetFieldValue<DateTimeOffset>(remindersReader.GetOrdinal("remind_at")),
                remindersReader.GetFieldValue<ReminderChannel>(remindersReader.GetOrdinal("channel")).ToString().ToLowerInvariant(),
                remindersReader.GetFieldValue<ReminderStatus>(remindersReader.GetOrdinal("status")).ToString().ToLowerInvariant()));
        }

        return activity with { Reminders = reminders };
    });

    public Task<ActivityResponse> UpdateAsync(Guid userId, Guid activityId, ActivityUpdateRequest request) =>
        RunAsync(async conn =>
        {
            ValidateMeeting(request.MeetingUrl, request.MeetingProvider);

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT * FROM fn_update_activity(
                    @user_id, @id, @title, @description,
                    @starts_at, @clear_starts_at, @ends_at, @clear_ends_at,
                    @status, @location, @meeting_url, @meeting_provider)";
            cmd.Parameters.AddWithValue("user_id", userId);
            cmd.Parameters.AddWithValue("id", activityId);
            cmd.Parameters.AddWithValue("title", (object?)request.Title ?? DBNull.Value);
            cmd.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("starts_at", (object?)request.StartsAt ?? DBNull.Value);
            cmd.Parameters.AddWithValue("clear_starts_at", request.ClearStartsAt);
            cmd.Parameters.AddWithValue("ends_at", (object?)request.EndsAt ?? DBNull.Value);
            cmd.Parameters.AddWithValue("clear_ends_at", request.ClearEndsAt);
            cmd.Parameters.Add(EnumParam("status", "activity_status", request.Status is null ? null : EnumParsing.Parse<ActivityStatus>(request.Status, "status")));
            cmd.Parameters.AddWithValue("location", (object?)request.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("meeting_url", (object?)request.MeetingUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("meeting_provider", (object?)request.MeetingProvider ?? DBNull.Value);

            await using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            return MapActivity(reader);
        });

    public Task CancelAsync(Guid userId, Guid activityId) =>
        // Soft delete: mismo contrato que DELETE /activities/{id} en la §6.
        UpdateAsync(userId, activityId, new ActivityUpdateRequest(
            null, null, null, false, null, false, "cancelled", null));

    // SPEC-003 (§5): defensa en profundidad — el cliente ya valida, pero el
    // servidor nunca confía solo en él. Solo valida cuando el campo viene con
    // contenido (NULL = "no lo toques"/"sin reunión", permitido por RF1).
    private static void ValidateMeeting(string? meetingUrl, string? meetingProvider)
    {
        if (meetingUrl is not null && !MeetingValidation.IsValidMeetingUrl(meetingUrl))
            throw new ApiException(400, "invalid_meeting_url", "meeting_url debe ser una URL http/https válida");

        if (meetingProvider is not null && !MeetingValidation.IsValidProvider(meetingProvider))
            throw new ApiException(400, "invalid_meeting_provider", "meeting_provider debe ser 'meet', 'teams' u 'other'");
    }

    private static ActivityResponse MapActivity(NpgsqlDataReader reader)
    {
        var contactIdOrdinal = reader.GetOrdinal("contact_id");
        return new ActivityResponse(
            reader.GetGuid(reader.GetOrdinal("id")),
            reader.GetGuid(reader.GetOrdinal("user_id")),
            reader.IsDBNull(contactIdOrdinal) ? null : reader.GetGuid(contactIdOrdinal),
            reader.GetFieldValue<ActivityType>(reader.GetOrdinal("type")).ToString().ToLowerInvariant(),
            reader.GetString(reader.GetOrdinal("title")),
            reader.IsDBNull(reader.GetOrdinal("description")) ? null : reader.GetString(reader.GetOrdinal("description")),
            reader.GetFieldValue<ActivityStatus>(reader.GetOrdinal("status")).ToString().ToLowerInvariant(),
            GetNullableDateTimeOffset(reader, "starts_at"),
            GetNullableDateTimeOffset(reader, "ends_at"),
            reader.GetString(reader.GetOrdinal("timezone")),
            reader.IsDBNull(reader.GetOrdinal("location")) ? null : reader.GetString(reader.GetOrdinal("location")),
            reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("created_at")),
            reader.GetFieldValue<DateTimeOffset>(reader.GetOrdinal("updated_at")),
            GetNullableString(reader, "meeting_url"),
            GetNullableString(reader, "meeting_provider"));
    }

    private static string? GetNullableString(NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    private static DateTimeOffset? GetNullableDateTimeOffset(NpgsqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetFieldValue<DateTimeOffset>(ordinal);
    }

    // AddWithValue no puede inferir el tipo de Postgres a partir de un DBNull.Value
    // desnudo (pierde el tipo al boxear). DataTypeName explícito hace que el
    // parámetro siempre viaje como activity_type/activity_status, tenga o no
    // valor, en vez de depender de cómo Postgres resuelva un "unknown" nulo.
    private static NpgsqlParameter EnumParam(string name, string pgTypeName, object? value) =>
        new(name, value ?? DBNull.Value) { DataTypeName = pgTypeName };
}
