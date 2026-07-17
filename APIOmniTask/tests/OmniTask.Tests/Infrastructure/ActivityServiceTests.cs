using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Pruebas de integración reales contra fn_create_activity, fn_update_activity
// y fn_get_activity_by_id (§23) — cubre las reglas de negocio que antes vivían
// en C# y ahora viven en el SQL: forzar unscheduled sin fecha, resincronizar
// status al reprogramar/limpiar la fecha, y cancelar reminders pendientes sin
// enviarlos. Se salta (no falla) sin un Postgres alcanzable.
[Collection("Database")]
public class ActivityServiceTests
{
    private readonly DatabaseFixture _fixture;
    private readonly ActivityService _activityService = null!;
    private readonly AuthService _authService = null!;

    public ActivityServiceTests(DatabaseFixture fixture)
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

    private static DateTimeOffset TruncateToMicroseconds(DateTimeOffset value) =>
        new(value.Ticks - (value.Ticks % 10), value.Offset);

    private static ActivityCreateRequest NewMeetingRequest(DateTimeOffset? startsAt) => new(
        Type: "meeting",
        Title: "Reunión de prueba",
        Description: "Descripción de prueba",
        ContactId: null,
        StartsAt: startsAt,
        EndsAt: startsAt?.AddHours(1),
        Location: "Sala 1");

    [SkippableFact]
    public async Task CreateAsync_con_fecha_queda_scheduled_y_genera_reminders()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var startsAt = DateTimeOffset.UtcNow.AddDays(2);

        var created = await _activityService.CreateAsync(userId, NewMeetingRequest(startsAt));
        Assert.Equal("scheduled", created.Status);

        var withReminders = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.NotNull(withReminders.Reminders);
        Assert.NotEmpty(withReminders.Reminders!);
        Assert.All(withReminders.Reminders!, r => Assert.Equal("pending", r.Status));
    }

    [SkippableFact]
    public async Task CreateAsync_sin_fecha_fuerza_unscheduled_y_no_genera_reminders()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();

        var created = await _activityService.CreateAsync(userId, NewMeetingRequest(null));
        Assert.Equal("unscheduled", created.Status);

        var withReminders = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.Empty(withReminders.Reminders!);
    }

    [SkippableFact]
    public async Task UpdateAsync_al_reprogramar_cancela_los_reminders_viejos_y_crea_nuevos()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var originalStart = DateTimeOffset.UtcNow.AddDays(2);
        var created = await _activityService.CreateAsync(userId, NewMeetingRequest(originalStart));

        // Postgres timestamptz solo guarda precisión de microsegundos; truncar
        // aquí evita que el round-trip pierda los últimos ticks (100ns) y el
        // Assert.Equal de más abajo falle por una diferencia de sub-microsegundo.
        var newStart = TruncateToMicroseconds(DateTimeOffset.UtcNow.AddDays(5));
        await _activityService.UpdateAsync(userId, created.Id, new ActivityUpdateRequest(
            Title: null, Description: null, StartsAt: newStart, ClearStartsAt: false,
            EndsAt: newStart.AddHours(1), ClearEndsAt: false, Status: null, Location: null));

        var reloaded = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.Equal("scheduled", reloaded.Status);
        Assert.Equal(newStart, reloaded.StartsAt);

        // fn_update_activity no borra los reminders viejos al reprogramar: los
        // marca 'failed' e inserta unos nuevos 'pending' — la lista trae ambos.
        var pendingReminders = reloaded.Reminders!.Where(r => r.Status == "pending").ToList();
        var failedReminders = reloaded.Reminders!.Where(r => r.Status == "failed").ToList();
        Assert.NotEmpty(pendingReminders);
        Assert.NotEmpty(failedReminders);
        Assert.All(pendingReminders, r => Assert.True(r.RemindAt < newStart));
    }

    [SkippableFact]
    public async Task UpdateAsync_con_clear_starts_at_regresa_la_actividad_al_backlog()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(userId, NewMeetingRequest(DateTimeOffset.UtcNow.AddDays(2)));

        var updated = await _activityService.UpdateAsync(userId, created.Id, new ActivityUpdateRequest(
            Title: null, Description: null, StartsAt: null, ClearStartsAt: true,
            EndsAt: null, ClearEndsAt: true, Status: null, Location: null));

        Assert.Equal("unscheduled", updated.Status);
        Assert.Null(updated.StartsAt);
    }

    [SkippableFact]
    public async Task CancelAsync_marca_los_reminders_pendientes_como_failed()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(userId, NewMeetingRequest(DateTimeOffset.UtcNow.AddDays(2)));

        await _activityService.CancelAsync(userId, created.Id);

        var reloaded = await _activityService.GetByIdAsync(userId, created.Id);
        Assert.Equal("cancelled", reloaded.Status);
        Assert.All(reloaded.Reminders!, r => Assert.Equal("failed", r.Status));
    }

    [SkippableFact]
    public async Task GetByIdAsync_con_actividad_de_otro_usuario_lanza_404()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var ownerId = await CreateTestUserAsync();
        var otherUserId = await CreateTestUserAsync();
        var created = await _activityService.CreateAsync(ownerId, NewMeetingRequest(DateTimeOffset.UtcNow.AddDays(2)));

        var ex = await Assert.ThrowsAsync<ApiException>(() => _activityService.GetByIdAsync(otherUserId, created.Id));
        Assert.Equal(404, ex.StatusCode);
    }
}
