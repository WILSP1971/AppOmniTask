using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Pruebas de integración reales de fn_create_activity / fn_update_activity
// extendidas con meeting_url / meeting_provider (SPEC-003, db/05_*.sql +
// db/06_*.sql). Se salta (no falla) sin un Postgres alcanzable — mismo
// patrón que ActivityServiceTests.
[Collection("Database")]
public class ActivityServiceMeetingTests
{
    private readonly DatabaseFixture _fixture;
    private readonly ActivityService _activityService = null!;
    private readonly AuthService _authService = null!;

    public ActivityServiceMeetingTests(DatabaseFixture fixture)
    {
        _fixture = fixture;

        if (!fixture.IsAvailable) return;

        _activityService = new ActivityService(fixture.DataSource);

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = "clave-de-prueba-de-al-menos-32-bytes!!",
            })
            .Build();
        _authService = new AuthService(fixture.DataSource, new Argon2PasswordHasher(), new JwtTokenFactory(config));
    }

    private async Task<Guid> CreateTestUserAsync()
    {
        var registered = await _authService.RegisterAsync(new RegisterRequest(
            FullName: "Usuario de Prueba",
            Email: $"{Guid.NewGuid():N}@clinicacampbell.test",
            Password: "clave-segura-123",
            PhoneE164: "+573000000000",
            Timezone: "America/Bogota"));
        return registered.User.Id;
    }

    private static ActivityCreateRequest MeetingRequest(
        DateTimeOffset? startsAt, string? meetingUrl = null, string? meetingProvider = null) => new(
        Type: "meeting",
        Title: "Reunión con link",
        Description: null,
        ContactId: null,
        StartsAt: startsAt,
        EndsAt: startsAt?.AddHours(1),
        Location: null,
        MeetingUrl: meetingUrl,
        MeetingProvider: meetingProvider);

    // CA1 + CA2: crear con meeting_url/meeting_provider y que persistan al reabrir (GET).
    [SkippableFact]
    public async Task CreateAsync_con_meeting_url_y_provider_persiste_y_se_puede_releer()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var startsAt = DateTimeOffset.UtcNow.AddDays(1);

        var created = await _activityService.CreateAsync(userId, MeetingRequest(
            startsAt, "https://meet.google.com/abc-defg-hij", "meet"));

        Assert.Equal("https://meet.google.com/abc-defg-hij", created.MeetingUrl);
        Assert.Equal("meet", created.MeetingProvider);

        var reloaded = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.Equal("https://meet.google.com/abc-defg-hij", reloaded.MeetingUrl);
        Assert.Equal("meet", reloaded.MeetingProvider);
    }

    // RF1: nulos permitidos (actividad sin reunión) — no se rompe nada al omitirlos.
    [SkippableFact]
    public async Task CreateAsync_sin_meeting_url_deja_los_campos_en_null()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(userId, MeetingRequest(DateTimeOffset.UtcNow.AddDays(1)));

        Assert.Null(created.MeetingUrl);
        Assert.Null(created.MeetingProvider);
    }

    // CA1: una URL con esquema inválido (ni http ni https) se rechaza con 400.
    [SkippableFact]
    public async Task CreateAsync_con_meeting_url_invalida_lanza_400()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();

        var ex = await Assert.ThrowsAsync<ApiException>(() => _activityService.CreateAsync(
            userId, MeetingRequest(DateTimeOffset.UtcNow.AddDays(1), "no-es-una-url", "meet")));

        Assert.Equal(400, ex.StatusCode);
    }

    // CA1: un meeting_provider fuera del conjunto permitido se rechaza con 400.
    [SkippableFact]
    public async Task CreateAsync_con_meeting_provider_no_permitido_lanza_400()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();

        var ex = await Assert.ThrowsAsync<ApiException>(() => _activityService.CreateAsync(
            userId, MeetingRequest(DateTimeOffset.UtcNow.AddDays(1), "https://meet.google.com/abc", "zoom")));

        Assert.Equal(400, ex.StatusCode);
    }

    // CA2: editar una actividad para agregar/cambiar el link también persiste.
    [SkippableFact]
    public async Task UpdateAsync_agrega_meeting_url_a_una_actividad_que_no_tenia()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(userId, MeetingRequest(DateTimeOffset.UtcNow.AddDays(1)));
        Assert.Null(created.MeetingUrl);

        var updated = await _activityService.UpdateAsync(userId, created.Id, new ActivityUpdateRequest(
            Title: null, Description: null, StartsAt: null, ClearStartsAt: false,
            EndsAt: null, ClearEndsAt: false, Status: null, Location: null,
            MeetingUrl: "https://teams.microsoft.com/l/meetup-join/xyz", MeetingProvider: "teams"));

        Assert.Equal("https://teams.microsoft.com/l/meetup-join/xyz", updated.MeetingUrl);
        Assert.Equal("teams", updated.MeetingProvider);
    }

    // CA7 / RNF5: la migración es aditiva — una actividad creada sin tocar
    // meeting_url/meeting_provider sigue funcionando con list/get/patch
    // normalmente (no se rompe nada existente).
    [SkippableFact]
    public async Task Actividad_sin_campos_de_reunion_sigue_funcionando_en_list_get_y_patch()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(userId, MeetingRequest(DateTimeOffset.UtcNow.AddDays(1)));

        var list = await _activityService.ListAsync(userId, null, null, null, null, 1, 50);
        Assert.Contains(list.Items, a => a.Id == created.Id && a.MeetingUrl == null);

        var fetched = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.Null(fetched.MeetingUrl);
        Assert.Null(fetched.MeetingProvider);

        var patched = await _activityService.UpdateAsync(userId, created.Id, new ActivityUpdateRequest(
            Title: "Título actualizado", Description: null, StartsAt: null, ClearStartsAt: false,
            EndsAt: null, ClearEndsAt: false, Status: null, Location: null));

        Assert.Equal("Título actualizado", patched.Title);
        Assert.Null(patched.MeetingUrl);
    }
}
