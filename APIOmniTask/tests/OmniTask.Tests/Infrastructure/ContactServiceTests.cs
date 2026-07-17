using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using OmniTask.Application.Dtos;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Pruebas de integración contra fn_create_contact / sp_delete_contact (§23) —
// en particular, la regla de que un contacto con actividades asociadas no se
// puede borrar (409), para no dejar actividades con un contact_id colgante.
[Collection("Database")]
public class ContactServiceTests
{
    private readonly DatabaseFixture _fixture;
    private readonly ContactService _contactService = null!;
    private readonly ActivityService _activityService = null!;
    private readonly AuthService _authService = null!;

    public ContactServiceTests(DatabaseFixture fixture)
    {
        _fixture = fixture;

        if (!fixture.IsAvailable) return;

        _contactService = new ContactService(fixture.DataSource);
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

    [SkippableFact]
    public async Task CreateAsync_crea_el_contacto()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();

        var contact = await _contactService.CreateAsync(
            userId, new ContactRequest("Contacto de Prueba", "+573001112233", "Notas"));

        Assert.Equal("Contacto de Prueba", contact.FullName);
    }

    [SkippableFact]
    public async Task DeleteAsync_sin_actividades_asociadas_lo_borra()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var contact = await _contactService.CreateAsync(
            userId, new ContactRequest("Contacto sin Actividades", "+573001112233", null));

        await _contactService.DeleteAsync(userId, contact.Id);

        var ex = await Assert.ThrowsAsync<ApiException>(() => _contactService.GetByIdAsync(userId, contact.Id));
        Assert.Equal(404, ex.StatusCode);
    }

    [SkippableFact]
    public async Task DeleteAsync_con_actividades_asociadas_lanza_409()
    {
        Skip.IfNot(_fixture.IsAvailable, "No hay Postgres alcanzable — ver TEST_DATABASE_URL");

        var userId = await CreateTestUserAsync();
        var contact = await _contactService.CreateAsync(
            userId, new ContactRequest("Contacto con Actividades", "+573001112233", null));

        await _activityService.CreateAsync(userId, new ActivityCreateRequest(
            Type: "meeting",
            Title: "Reunión con el contacto",
            Description: null,
            ContactId: contact.Id,
            StartsAt: DateTimeOffset.UtcNow.AddDays(1),
            EndsAt: DateTimeOffset.UtcNow.AddDays(1).AddHours(1),
            Location: null));

        var ex = await Assert.ThrowsAsync<ApiException>(() => _contactService.DeleteAsync(userId, contact.Id));
        Assert.Equal(409, ex.StatusCode);
    }
}
