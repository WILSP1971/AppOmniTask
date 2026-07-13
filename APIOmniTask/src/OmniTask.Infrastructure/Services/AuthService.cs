using NpgsqlTypes;
using Npgsql;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;

namespace OmniTask.Infrastructure.Services;

public class AuthService : SqlServiceBase, IAuthService
{
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITokenFactory _tokenFactory;

    // Hash de un password fijo, calculado una sola vez con el mismo hasher
    // inyectado, para que el camino de "usuario no existe" tarde
    // aproximadamente lo mismo que "contraseña incorrecta" — evita un canal
    // de tiempo que permita enumerar correos.
    private readonly Lazy<string> _dummyHashForTimingParity;

    public AuthService(NpgsqlDataSource dataSource, IPasswordHasher passwordHasher, ITokenFactory tokenFactory)
        : base(dataSource)
    {
        _passwordHasher = passwordHasher;
        _tokenFactory = tokenFactory;
        _dummyHashForTimingParity = new Lazy<string>(() => _passwordHasher.Hash("no-existe-este-usuario"));
    }

    public async Task<RegisterResponse> RegisterAsync(RegisterRequest request)
    {
        var user = await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_register_user(@full_name, @email, @password_hash, @phone_e164, @timezone)";
            cmd.Parameters.AddWithValue("full_name", request.FullName);
            cmd.Parameters.AddWithValue("email", request.Email);
            cmd.Parameters.AddWithValue("password_hash", _passwordHasher.Hash(request.Password));
            cmd.Parameters.AddWithValue("phone_e164", request.PhoneE164);
            cmd.Parameters.AddWithValue("timezone", request.Timezone);

            await using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            return MapUser(reader);
        });

        var tokens = await IssueTokenPairAsync(user.Id);
        return new RegisterResponse(user, tokens.AccessToken, tokens.RefreshToken);
    }

    private sealed record LoginLookup(UserResponse? User, string? PasswordHash);

    public async Task<TokenPairResponse> LoginAsync(LoginRequest request)
    {
        var lookup = await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_get_user_by_email(@email)";
            cmd.Parameters.AddWithValue("email", request.Email);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return new LoginLookup(null, null);
            return new LoginLookup(MapUser(reader), reader.GetString(reader.GetOrdinal("password_hash")));
        });

        // Verificar siempre, aunque el usuario no exista (con un hash fijo), evita
        // que el tiempo de respuesta delate si el correo está registrado o no.
        var isValid = lookup.User is not null && _passwordHasher.Verify(request.Password, lookup.PasswordHash!);
        if (!isValid)
        {
            _passwordHasher.Verify(request.Password, _dummyHashForTimingParity.Value);
            throw new ApiException(401, "invalid_credentials", "Credenciales inválidas");
        }

        return await IssueTokenPairAsync(lookup.User!.Id);
    }

    public async Task<TokenPairResponse> RefreshAsync(string refreshToken)
    {
        var jti = _tokenFactory.ReadRefreshJti(refreshToken);

        var userId = await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_rotate_refresh_token(@jti)";
            cmd.Parameters.AddWithValue("jti", jti);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync()) return (Guid?)null;
            return reader.GetGuid(0);
        });

        if (userId is null)
            throw new ApiException(401, "session_expired", "Sesión expirada, inicia sesión de nuevo");

        return await IssueTokenPairAsync(userId.Value);
    }

    public async Task LogoutAsync(string refreshToken)
    {
        var jti = _tokenFactory.ReadRefreshJti(refreshToken);
        await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "CALL sp_revoke_refresh_token(@jti)";
            cmd.Parameters.AddWithValue("jti", jti);
            await cmd.ExecuteNonQueryAsync();
        });
    }

    public async Task<UserResponse> GetProfileAsync(Guid userId) => await RunAsync(async conn =>
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT * FROM fn_get_user_by_id(@id)";
        cmd.Parameters.AddWithValue("id", userId);

        await using var reader = await cmd.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            throw new ApiException(404, "not_found", "Usuario no encontrado");
        return MapUser(reader);
    });

    public async Task<UserResponse> UpdateProfileAsync(Guid userId, UpdateProfileRequest request) =>
        await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT * FROM fn_update_user_profile(@id, @full_name, @phone_e164, @timezone, @preferences)";
            cmd.Parameters.AddWithValue("id", userId);
            cmd.Parameters.AddWithValue("full_name", (object?)request.FullName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("phone_e164", (object?)request.PhoneE164 ?? DBNull.Value);
            cmd.Parameters.AddWithValue("timezone", (object?)request.Timezone ?? DBNull.Value);

            var preferencesParam = new NpgsqlParameter("preferences", NpgsqlDbType.Jsonb)
            {
                Value = request.NotificationPreferences is null
                    ? DBNull.Value
                    : NotificationPreferencesJson.Serialize(request.NotificationPreferences),
            };
            cmd.Parameters.Add(preferencesParam);

            await using var reader = await cmd.ExecuteReaderAsync();
            if (!await reader.ReadAsync())
                throw new ApiException(404, "not_found", "Usuario no encontrado");
            return MapUser(reader);
        });

    private async Task<TokenPairResponse> IssueTokenPairAsync(Guid userId)
    {
        var accessToken = _tokenFactory.CreateAccessToken(userId);
        var (refreshToken, jti, expiresAt) = _tokenFactory.CreateRefreshToken(userId);

        await RunAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "CALL sp_create_refresh_token(@jti, @user_id, @expires_at)";
            cmd.Parameters.AddWithValue("jti", jti);
            cmd.Parameters.AddWithValue("user_id", userId);
            cmd.Parameters.AddWithValue("expires_at", expiresAt);
            await cmd.ExecuteNonQueryAsync();
        });

        return new TokenPairResponse(accessToken, refreshToken);
    }

    private static UserResponse MapUser(NpgsqlDataReader reader)
    {
        var preferencesJson = reader.GetString(reader.GetOrdinal("notification_preferences"));
        return new UserResponse(
            reader.GetGuid(reader.GetOrdinal("id")),
            reader.GetString(reader.GetOrdinal("full_name")),
            reader.GetString(reader.GetOrdinal("email")),
            reader.GetString(reader.GetOrdinal("phone_e164")),
            reader.GetString(reader.GetOrdinal("timezone")),
            reader.GetFieldValue<UserRole>(reader.GetOrdinal("role")).ToString().ToLowerInvariant(),
            NotificationPreferencesJson.Parse(preferencesJson));
    }
}
