using Npgsql;
using OmniTask.Domain;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

/// Compartida entre las clases de prueba de integración (§23): intenta abrir
/// una conexión real una sola vez. Si no hay Postgres alcanzable — el caso
/// normal al correr `dotnet test` fuera de CI, sin el service container de
/// backend-ci.yml — IsAvailable queda en false y las pruebas se saltan en
/// vez de fallar con un error de conexión que no dice nada útil.
public class DatabaseFixture : IAsyncLifetime
{
    public NpgsqlDataSource DataSource { get; private set; } = null!;
    public bool IsAvailable { get; private set; }

    public async Task InitializeAsync()
    {
        var connectionString = Environment.GetEnvironmentVariable("TEST_DATABASE_URL")
            ?? "Host=localhost;Port=5432;Database=omnitask_test;Username=postgres;Password=test";

        var builder = new NpgsqlDataSourceBuilder(connectionString);
        builder.MapEnum<UserRole>("user_role");
        builder.MapEnum<DevicePlatform>("device_platform");
        builder.MapEnum<ActivityType>("activity_type");
        builder.MapEnum<ActivityStatus>("activity_status");
        builder.MapEnum<ReminderChannel>("reminder_channel");
        builder.MapEnum<ReminderStatus>("reminder_status");
        builder.MapEnum<NotificationChannel>("notification_channel");
        builder.MapEnum<NotificationStatus>("notification_status");
        builder.MapEnum<TemplateCategory>("template_category");
        builder.MapEnum<TemplateApprovalStatus>("template_approval_status");

        try
        {
            DataSource = builder.Build();
            await using var connection = await DataSource.OpenConnectionAsync();
            IsAvailable = true;
        }
        catch
        {
            IsAvailable = false;
        }
    }

    public async Task DisposeAsync()
    {
        if (DataSource is not null)
        {
            await DataSource.DisposeAsync();
        }
    }
}

[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
}
