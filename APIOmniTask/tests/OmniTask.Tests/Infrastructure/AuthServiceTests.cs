using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Pruebas de integración reales contra fn_register_user, fn_get_user_by_email,
// fn_rotate_refresh_token, sp_revoke_refresh_token y fn_update_user_profile
// (§23) — no mocks: si el SQL y el C# se desincronizan, esto es lo primero
// que debería fallar. Se saltan (no fallan) sin un Postgres alcanzable.
[Collection("Database")]
public class AuthServiceTests
{
    private readonly DatabaseFixture _fixture;
    private readonly AuthService _authService;

    public AuthServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = "clave-de-prueba-de-al-menos-32-bytes!!",
            })
            .Build();

        _authService = fixture.IsAvailable
            ? new AuthService(fixture.DataSource, new Argon2PasswordHasher(), new JwtTokenFactory(config))
            : null!;
    }

    private static string UniqueEmail() => $"{Guid.NewGuid():N}@clinicacampbell.test";

    private Task<RegisterResponse> RegisterTestUserAsync(string? email = null, string password = "clave-segura-123") =>
        _authService.RegisterAsync(new RegisterRequest(
            FullName: "Usuario de Prueba",
            Email: email ?? UniqueEmail(),
            Password: password,
            PhoneE164: "+573000000000",
            Timezone: "America/Bogota"));

    [SkippableFact]
    public async Task RegisterAsync_crea_el_usuario_y_emite_ambos_tokens()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var response = await RegisterTestUserAsync();

        Assert.NotEqual(Guid.Empty.ToString(), response.User.Id.ToString());
        Assert.False(string.IsNullOrEmpty(response.AccessToken));
        Assert.False(string.IsNullOrEmpty(response.RefreshToken));
    }

    [SkippableFact]
    public async Task RegisterAsync_con_correo_repetido_lanza_409()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var email = UniqueEmail();
        await RegisterTestUserAsync(email);

        var ex = await Assert.ThrowsAsync<ApiException>(() => RegisterTestUserAsync(email));
        Assert.Equal(409, ex.StatusCode);
    }

    [SkippableFact]
    public async Task LoginAsync_con_contraseña_incorrecta_lanza_401()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var email = UniqueEmail();
        await RegisterTestUserAsync(email, "la-correcta-123");

        var ex = await Assert.ThrowsAsync<ApiException>(
            () => _authService.LoginAsync(new LoginRequest(email, "no-es-esta")));
        Assert.Equal(401, ex.StatusCode);
    }

    [SkippableFact]
    public async Task LoginAsync_con_credenciales_correctas_emite_tokens()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var email = UniqueEmail();
        await RegisterTestUserAsync(email, "la-correcta-123");

        var tokens = await _authService.LoginAsync(new LoginRequest(email, "la-correcta-123"));
        Assert.False(string.IsNullOrEmpty(tokens.AccessToken));
    }

    // El caso más importante de todo el archivo: fn_rotate_refresh_token
    // (§10, §23) revoca y devuelve el user_id en el mismo UPDATE atómico —
    // reutilizar un refresh token ya usado debe fallar, no emitir un par nuevo.
    [SkippableFact]
    public async Task RefreshAsync_rota_el_token_y_rechaza_la_reutilización()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var registered = await RegisterTestUserAsync();
        var firstRefreshToken = registered.RefreshToken;

        var rotated = await _authService.RefreshAsync(firstRefreshToken);
        Assert.NotEqual(firstRefreshToken, rotated.RefreshToken);

        var ex = await Assert.ThrowsAsync<ApiException>(() => _authService.RefreshAsync(firstRefreshToken));
        Assert.Equal(401, ex.StatusCode);
    }

    [SkippableFact]
    public async Task LogoutAsync_revoca_el_refresh_token()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var registered = await RegisterTestUserAsync();

        await _authService.LogoutAsync(registered.RefreshToken);

        var ex = await Assert.ThrowsAsync<ApiException>(() => _authService.RefreshAsync(registered.RefreshToken));
        Assert.Equal(401, ex.StatusCode);
    }

    [SkippableFact]
    public async Task UpdateProfileAsync_persiste_los_cambios()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var registered = await RegisterTestUserAsync();
        var userId = registered.User.Id;

        var updated = await _authService.UpdateProfileAsync(
            userId, new UpdateProfileRequest("Nombre Actualizado", null, null, null));
        Assert.Equal("Nombre Actualizado", updated.FullName);

        var reloaded = await _authService.GetProfileAsync(userId);
        Assert.Equal("Nombre Actualizado", reloaded.FullName);
    }
}
