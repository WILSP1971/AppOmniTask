using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Konscious.Security.Cryptography;
using Microsoft.IdentityModel.Tokens;
using OmniTask.Application;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api;

// Argon2id en vez de bcrypt (§10) — sin el límite de 72 bytes, recomendación
// actual de OWASP para contraseñas nuevas.
public class Argon2PasswordHasher : IPasswordHasher
{
    public string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = DeriveKey(password, salt);
        return $"{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
    }

    public bool Verify(string password, string stored)
    {
        var parts = stored.Split(':');
        var salt = Convert.FromBase64String(parts[0]);
        var expected = Convert.FromBase64String(parts[1]);
        var actual = DeriveKey(password, salt);
        return CryptographicOperations.FixedTimeEquals(expected, actual);
    }

    private static byte[] DeriveKey(string password, byte[] salt)
    {
        using var argon2 = new Argon2id(Encoding.UTF8.GetBytes(password))
        {
            Salt = salt,
            DegreeOfParallelism = 4,
            Iterations = 4,
            MemorySize = 65536, // 64 MB
        };
        return argon2.GetBytes(32);
    }
}

// Access token de 15 min, refresh de 30 días con jti propio (§10) — el jti se
// guarda en la tabla refresh_tokens (Postgres) para poder revocarlo antes de
// que expire por sí solo, sin depender de Redis.
public class JwtTokenFactory : ITokenFactory
{
    private static readonly TimeSpan AccessTokenTtl = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan RefreshTokenTtl = TimeSpan.FromDays(30);

    private readonly string _secret;

    public JwtTokenFactory(IConfiguration config) => _secret = config["Jwt:Secret"]!;

    public string CreateAccessToken(Guid userId) =>
        CreateToken(userId, "access", AccessTokenTtl, out _, out _);

    public (string Token, Guid Jti, DateTimeOffset ExpiresAt) CreateRefreshToken(Guid userId)
    {
        var token = CreateToken(userId, "refresh", RefreshTokenTtl, out var jti, out var expiresAt);
        return (token, jti, expiresAt);
    }

    public Guid ReadRefreshJti(string token)
    {
        var handler = new JwtSecurityTokenHandler();
        ClaimsPrincipal principal;
        try
        {
            principal = handler.ValidateToken(token, ValidationParameters(), out _);
        }
        catch (Exception)
        {
            throw new ApiException(401, "invalid_token", "Token inválido");
        }

        if (principal.FindFirstValue("type") != "refresh")
            throw new ApiException(401, "invalid_token", "Se requiere un refresh token");

        return Guid.Parse(principal.FindFirstValue(JwtRegisteredClaimNames.Jti)!);
    }

    private string CreateToken(Guid userId, string type, TimeSpan ttl, out Guid jti, out DateTimeOffset expiresAt)
    {
        jti = Guid.NewGuid();
        expiresAt = DateTimeOffset.UtcNow.Add(ttl);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new Claim("type", type),
            new Claim(JwtRegisteredClaimNames.Jti, jti.ToString()),
        };
        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret)), SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(claims: claims, expires: expiresAt.UtcDateTime, signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private TokenValidationParameters ValidationParameters() => new()
    {
        ValidateIssuer = false,
        ValidateAudience = false,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret)),
    };
}

public static class ClaimsPrincipalExtensions
{
    public static Guid GetUserId(this ClaimsPrincipal principal) =>
        Guid.Parse(principal.FindFirstValue(JwtRegisteredClaimNames.Sub)!);
}

// Traduce ApiException al mismo sobre {"error": {"code", "message"}} de la §6.
public class ApiExceptionMiddleware
{
    private readonly RequestDelegate _next;

    public ApiExceptionMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (ApiException ex)
        {
            context.Response.StatusCode = ex.StatusCode;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(new { error = new { code = ex.Code, message = ex.Message } });
        }
    }
}
