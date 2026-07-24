using Npgsql;
using NpgsqlTypes;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using System.Text.Json;

namespace OmniTask.Infrastructure.Services;

public class ActivityService : SqlServiceBase, IActivityService
{
    public ActivityService(NpgsqlDataSource dataSource) : base(dataSource)
    {
    }

    public Task<ActivityResponse> CreateAsync(Guid userId, ActivityCreateRequest request) => RunAsync(async conn =>
    {
        ValidateMeeting(request.MeetingUrl, request.MeetingProvider);

        // SPEC-008 (RF10/RF12): une ContactIds (contrato nuevo) con ContactId
        // (legado, app vieja que solo manda un contacto) en un solo array
        // de-duplicado; si no llega ninguno de los dos, se pasa un array vacío.
        var contactIds = MergeContactIds(request.ContactId, request.ContactIds);

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_create_activity(@user_id, @contact_ids, @type, @title, @description, @starts_at, @ends_at, @location, @meeting_url, @meeting_provider)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.Add(new NpgsqlParameter("contact_ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = contactIds });
        cmd.Parameters.Add(EnumParam("type", "activity_type", EnumParsing.Parse<ActivityType>(request.Type, "type")));
        cmd.Parameters.AddWithValue("title", request.Title);
        cmd.Parameters.AddWithValue("description", (object?)request.Description ?? DBNull.Value);
        cmd.Parameters.AddWithValue("starts_at", (object?)request.StartsAt ?? DBNull.Value);
        cmd.Parameters.AddWithValue("ends_at", (object?)request.EndsAt ?? DBNull.Value);
        cmd.Parameters.AddWithValue("location", (object?)request.Location ?? DBNull.Value);
        cmd.Parameters.AddWithValue("meeting_url", (object?)request.MeetingUrl ?? DBNull.Value);
        cmd.Parameters.AddWithValue("meeting_provider", (object?)request.MeetingProvider ?? DBNull.Value);

        ActivityResponse activity;
        await using (var reader = await cmd.ExecuteReaderAsync())
        {
            await reader.ReadAsync();
            activity = MapActivity(reader);
        }

        // fn_create_activity (RF4) sigue siendo SETOF activities puro (sin la
        // columna "contacts", que solo agregan las funciones de lectura del
        // RF6): se completa la lista de contactos con una segunda consulta
        // para que la respuesta cumpla CA1 (contacts con todos los asociados).
        return await LoadContactsAsync(conn, userId, activity);
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

            // SPEC-008 (RF5/RF10): ContactIds null = no tocar los contactos
            // (p_sync_contacts = false); una lista, incluso vacía, reemplaza
            // el conjunto completo (p_sync_contacts = true).
            var syncContacts = request.ContactIds is not null;
            var contactIds = request.ContactIds?.Distinct().ToArray() ?? Array.Empty<Guid>();

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT * FROM fn_update_activity(
                    @user_id, @id, @title, @description,
                    @starts_at, @clear_starts_at, @ends_at, @clear_ends_at,
                    @status, @location, @meeting_url, @meeting_provider,
                    @contact_ids, @sync_contacts)";
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
            cmd.Parameters.Add(new NpgsqlParameter("contact_ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = contactIds });
            cmd.Parameters.AddWithValue("sync_contacts", syncContacts);

            ActivityResponse activity;
            await using (var reader = await cmd.ExecuteReaderAsync())
            {
                await reader.ReadAsync();
                activity = MapActivity(reader);
            }

            // Igual que en CreateAsync: fn_update_activity (RF5) es SETOF
            // activities puro, se completa "contacts" con una segunda consulta
            // para reflejar el conjunto ya sincronizado (CA2).
            return await LoadContactsAsync(conn, userId, activity);
        });

    public Task CancelAsync(Guid userId, Guid activityId) =>
        // Soft delete: mismo contrato que DELETE /activities/{id} en la §6.
        UpdateAsync(userId, activityId, new ActivityUpdateRequest(
            null, null, null, false, null, false, "cancelled", null));

    // SPEC-008 (RF10/RF12): une ContactId (legado, un solo id) con ContactIds
    // (nuevo, 0..N ids) en un solo array de-duplicado; nulos se descartan.
    private static Guid[] MergeContactIds(Guid? legacyContactId, List<Guid>? contactIds)
    {
        var merged = new List<Guid>();
        if (legacyContactId is Guid legacy) merged.Add(legacy);
        if (contactIds is not null) merged.AddRange(contactIds);
        return merged.Distinct().ToArray();
    }

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
        // SPEC-008 (RF10): los contactos ahora salen de la columna agregada
        // "contacts" JSONB (fuente de verdad: activity_contacts); contact_id
        // legado se deriva del primer contacto de la lista, no de la columna
        // activities.contact_id (deprecada, RF3), para reflejar siempre el
        // estado real de la tabla puente.
        var contacts = ParseContacts(reader);
        return new ActivityResponse(
            reader.GetGuid(reader.GetOrdinal("id")),
            reader.GetGuid(reader.GetOrdinal("user_id")),
            contacts.Count > 0 ? contacts[0].Id : null,
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
            GetNullableString(reader, "meeting_provider"),
            Contacts: contacts);
    }

    // fn_get_activity_by_id (RF6) ya trae "contacts" completo; se reusa aquí
    // para completar la respuesta de create/update sin duplicar el jsonb_agg
    // en SQL. userId se pasa explícito (no confiar en scoping implícito) para
    // mantener el mismo filtro de propiedad que el resto del servicio.
    private static async Task<ActivityResponse> LoadContactsAsync(NpgsqlConnection conn, Guid userId, ActivityResponse activity)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT contacts FROM fn_get_activity_by_id(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", activity.Id);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return activity;

        var contacts = ParseContacts(reader);
        return activity with { Contacts = contacts, ContactId = contacts.Count > 0 ? contacts[0].Id : null };
    }

    // Lee la columna agregada "contacts" JSONB ({id, full_name, phone_e164}[])
    // que devuelven fn_get_activity_by_id/fn_list_activities/
    // fn_list_unscheduled_activities (RF6); notes no viaja en el agregado SQL
    // (no se pidió por la SPEC), así que ContactResponse.Notes queda null.
    // fn_create_activity/fn_update_activity (RF4/RF5) siguen siendo SETOF
    // activities puro -- no traen la columna "contacts" -- así que aquí se
    // devuelve lista vacía y CreateAsync/UpdateAsync la completan aparte
    // (ver llamada a fn_get_activity_by_id tras crear/actualizar).
    private static List<ContactResponse> ParseContacts(NpgsqlDataReader reader)
    {
        int ordinal;
        try
        {
            ordinal = reader.GetOrdinal("contacts");
        }
        catch (IndexOutOfRangeException)
        {
            return new List<ContactResponse>();
        }
        if (reader.IsDBNull(ordinal)) return new List<ContactResponse>();

        var json = reader.GetString(ordinal);
        var items = JsonSerializer.Deserialize<List<JsonElement>>(json) ?? new List<JsonElement>();

        var result = new List<ContactResponse>();
        foreach (var item in items)
        {
            var id = item.GetProperty("id").GetGuid();
            var fullName = item.GetProperty("full_name").GetString() ?? string.Empty;
            var phoneE164 = item.TryGetProperty("phone_e164", out var phoneEl) ? phoneEl.GetString() : null;
            result.Add(new ContactResponse(id, fullName, phoneE164 ?? string.Empty, null));
        }
        return result;
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
