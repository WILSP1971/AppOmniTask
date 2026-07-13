using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Domain.Entities;

namespace OmniTask.Application.Services;

// Depende de abstracciones inyectadas desde la capa Api (hashing, tokens, DbContext)
// para no acoplar Application a paquetes concretos de Infraestructura/ASP.NET.
public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string password, string hash);
}

public interface ITokenFactory
{
    string CreateAccessToken(Guid userId);
    (string Token, Guid Jti, DateTimeOffset ExpiresAt) CreateRefreshToken(Guid userId);
    Guid ReadRefreshJti(string token);
}

public class AuthService : IAuthService
{
    private readonly DbContext _db;
    private readonly DbSet<User> _users;
    private readonly DbSet<RefreshToken> _refreshTokens;
    private readonly IPasswordHasher _passwordHasher;
    private readonly ITokenFactory _tokenFactory;

    public AuthService(DbContext db, IPasswordHasher passwordHasher, ITokenFactory tokenFactory)
    {
        _db = db;
        _users = db.Set<User>();
        _refreshTokens = db.Set<RefreshToken>();
        _passwordHasher = passwordHasher;
        _tokenFactory = tokenFactory;
    }

    public async Task<RegisterResponse> RegisterAsync(RegisterRequest request)
    {
        if (await _users.AnyAsync(u => u.Email == request.Email))
            throw new ApiException(409, "email_taken", "Ya existe una cuenta con ese correo.");

        var user = new User
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName,
            Email = request.Email,
            PasswordHash = _passwordHasher.Hash(request.Password),
            PhoneE164 = request.PhoneE164,
            Timezone = request.Timezone,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
        _users.Add(user);
        await _db.SaveChangesAsync();

        var tokens = await IssueTokenPairAsync(user.Id);
        return new RegisterResponse(ToResponse(user), tokens.AccessToken, tokens.RefreshToken);
    }

    public async Task<TokenPairResponse> LoginAsync(LoginRequest request)
    {
        var user = await _users.SingleOrDefaultAsync(u => u.Email == request.Email);
        if (user is null || !_passwordHasher.Verify(request.Password, user.PasswordHash))
            throw new ApiException(401, "invalid_credentials", "Credenciales inválidas");

        return await IssueTokenPairAsync(user.Id);
    }

    public async Task<TokenPairResponse> RefreshAsync(string refreshToken)
    {
        var jti = _tokenFactory.ReadRefreshJti(refreshToken);

        var stored = await _refreshTokens.SingleOrDefaultAsync(t => t.Jti == jti);
        if (stored is null || stored.RevokedAt is not null || stored.ExpiresAt < DateTimeOffset.UtcNow)
            throw new ApiException(401, "session_expired", "Sesión expirada, inicia sesión de nuevo");

        // De un solo uso: revocar antes de emitir el reemplazo (§10) — si alguien
        // reutiliza un refresh token ya usado, esta llamada ya no lo encuentra válido.
        stored.RevokedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();

        return await IssueTokenPairAsync(stored.UserId);
    }

    public async Task LogoutAsync(string refreshToken)
    {
        var jti = _tokenFactory.ReadRefreshJti(refreshToken);
        var stored = await _refreshTokens.SingleOrDefaultAsync(t => t.Jti == jti);
        if (stored is not null && stored.RevokedAt is null)
        {
            stored.RevokedAt = DateTimeOffset.UtcNow;
            await _db.SaveChangesAsync();
        }
    }

    public async Task<UserResponse> GetProfileAsync(Guid userId)
    {
        var user = await _users.FindAsync(userId)
            ?? throw new ApiException(404, "not_found", "Usuario no encontrado");
        return ToResponse(user);
    }

    public async Task<UserResponse> UpdateProfileAsync(Guid userId, UpdateProfileRequest request)
    {
        var user = await _users.FindAsync(userId)
            ?? throw new ApiException(404, "not_found", "Usuario no encontrado");

        // El correo no se edita aquí a propósito (§16) — es la identidad de login,
        // cambiarla merece un flujo aparte con re-verificación.
        if (request.FullName is not null) user.FullName = request.FullName;
        if (request.PhoneE164 is not null) user.PhoneE164 = request.PhoneE164;
        if (request.Timezone is not null) user.Timezone = request.Timezone;
        if (request.NotificationPreferences is not null)
        {
            user.NotificationPreferences.DefaultChannel = request.NotificationPreferences.DefaultChannel;
            user.NotificationPreferences.ReminderOffsetsMinutes = request.NotificationPreferences.ReminderOffsetsMinutes;
        }

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
        return ToResponse(user);
    }

    private async Task<TokenPairResponse> IssueTokenPairAsync(Guid userId)
    {
        var accessToken = _tokenFactory.CreateAccessToken(userId);
        var (refreshToken, jti, expiresAt) = _tokenFactory.CreateRefreshToken(userId);

        _refreshTokens.Add(new RefreshToken { Jti = jti, UserId = userId, ExpiresAt = expiresAt });
        await _db.SaveChangesAsync();

        return new TokenPairResponse(accessToken, refreshToken);
    }

    private static UserResponse ToResponse(User user) => new(
        user.Id,
        user.FullName,
        user.Email,
        user.PhoneE164,
        user.Timezone,
        user.Role.ToString().ToLowerInvariant(),
        new NotificationPreferencesDto(
            user.NotificationPreferences.DefaultChannel,
            user.NotificationPreferences.ReminderOffsetsMinutes));
}
