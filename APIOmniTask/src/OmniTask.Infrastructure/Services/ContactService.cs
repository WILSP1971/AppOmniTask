using Npgsql;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Infrastructure.Services;

public class ContactService : SqlServiceBase, IContactService
{
    public ContactService(NpgsqlDataSource dataSource) : base(dataSource)
    {
    }

    public Task<ContactResponse> CreateAsync(Guid userId, ContactRequest request) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_create_contact(@user_id, @full_name, @phone_e164, @notes)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("full_name", request.FullName);
        cmd.Parameters.AddWithValue("phone_e164", request.PhoneE164);
        cmd.Parameters.AddWithValue("notes", (object?)request.Notes ?? DBNull.Value);

        await using var reader = await cmd.ExecuteReaderAsync();
        await reader.ReadAsync();
        return MapContact(reader);
    });

    public Task<List<ContactResponse>> ListAsync(Guid userId, string? search) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_list_contacts(@user_id, @search)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("search", (object?)search ?? DBNull.Value);

        var items = new List<ContactResponse>();
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync()) items.Add(MapContact(reader));
        return items;
    });

    public Task<ContactResponse> GetByIdAsync(Guid userId, Guid contactId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_get_contact_by_id(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", contactId);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new ApiException(404, "not_found", "Contacto no encontrado");
        return MapContact(reader);
    });

    public Task<ContactResponse> UpdateAsync(Guid userId, Guid contactId, ContactRequest request) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_update_contact(@user_id, @id, @full_name, @phone_e164, @notes)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", contactId);
        cmd.Parameters.AddWithValue("full_name", request.FullName);
        cmd.Parameters.AddWithValue("phone_e164", request.PhoneE164);
        cmd.Parameters.AddWithValue("notes", (object?)request.Notes ?? DBNull.Value);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new ApiException(404, "not_found", "Contacto no encontrado");
        return MapContact(reader);
    });

    public Task DeleteAsync(Guid userId, Guid contactId) => RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_delete_contact(@user_id, @id)";
        cmd.Parameters.AddWithValue("user_id", userId);
        cmd.Parameters.AddWithValue("id", contactId);
        await cmd.ExecuteNonQueryAsync();
    });

    private static ContactResponse MapContact(NpgsqlDataReader reader) => new(
        reader.GetGuid(reader.GetOrdinal("id")),
        reader.GetString(reader.GetOrdinal("full_name")),
        reader.GetString(reader.GetOrdinal("phone_e164")),
        reader.IsDBNull(reader.GetOrdinal("notes")) ? null : reader.GetString(reader.GetOrdinal("notes")));
}
