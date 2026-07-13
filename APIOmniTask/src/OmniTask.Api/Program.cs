using System.Text;
using System.Text.Json;
using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using OmniTask.Api;
using OmniTask.Application.Interfaces;
using OmniTask.Domain;
using OmniTask.Infrastructure.BackgroundJobs;
using OmniTask.Infrastructure.ExternalServices;
using OmniTask.Infrastructure.Services;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Default")!;

// Mapeo nativo de los ENUM de Postgres (schema.sql) a enums de C# — evita
// convertir manualmente cada valor en cada llamada a una función/procedimiento.
var dataSourceBuilder = new NpgsqlDataSourceBuilder(connectionString);
dataSourceBuilder.MapEnum<UserRole>("user_role");
dataSourceBuilder.MapEnum<DevicePlatform>("device_platform");
dataSourceBuilder.MapEnum<ActivityType>("activity_type");
dataSourceBuilder.MapEnum<ActivityStatus>("activity_status");
dataSourceBuilder.MapEnum<ReminderChannel>("reminder_channel");
dataSourceBuilder.MapEnum<ReminderStatus>("reminder_status");
dataSourceBuilder.MapEnum<NotificationChannel>("notification_channel");
dataSourceBuilder.MapEnum<NotificationStatus>("notification_status");
dataSourceBuilder.MapEnum<TemplateCategory>("template_category");
dataSourceBuilder.MapEnum<TemplateApprovalStatus>("template_approval_status");
var dataSource = dataSourceBuilder.Build();

// Sin EF Core: todas las lecturas/escrituras pasan por las funciones y
// procedimientos de db/03_stored_procedures_and_functions.sql (§23) — este
// NpgsqlDataSource es el único punto de acceso a la base para toda la API.
builder.Services.AddSingleton(dataSource);

// Hangfire reemplaza Celery+Redis (§8) usando el mismo Postgres como storage
// de jobs — un motor menos que operar en el servidor Windows (§18).
builder.Services.AddHangfire(config => config.UsePostgreSqlStorage(connectionString));
builder.Services.AddHangfireServer();

builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IActivityService, ActivityService>();
builder.Services.AddScoped<IContactService, ContactService>();
builder.Services.AddScoped<IDeviceService, DeviceService>();
builder.Services.AddScoped<INotificationService, NotificationService>();
builder.Services.AddSingleton<IPasswordHasher, Argon2PasswordHasher>();
builder.Services.AddSingleton<ITokenFactory, JwtTokenFactory>();
builder.Services.AddSingleton<IPushSender, FirebasePushSender>();
builder.Services.AddHttpClient<IWhatsAppClient, WhatsAppCloudApiClient>();
builder.Services.AddScoped<ReminderDispatchJob>();
builder.Services.AddScoped<UnscheduledDigestJob>();

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,
            ValidateAudience = false,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!)),
        };
        options.Events = new JwtBearerEvents
        {
            // Un refresh token nunca debe servir para autenticar una ruta protegida (§10).
            OnTokenValidated = context =>
            {
                var type = context.Principal?.FindFirst("type")?.Value;
                if (type != "access") context.Fail("Se requiere un access token");
                return Task.CompletedTask;
            },
        };
    });
builder.Services.AddAuthorization();

builder.Services
    .AddControllers()
    .AddJsonOptions(options =>
    {
        // Todo el contrato documentado (§6, §9, §16, §17) y el cliente Flutter
        // (§12, §15) usan snake_case — el default de ASP.NET Core es camelCase,
        // que rompería tanto las respuestas como el enlazado de los bodies entrantes.
        options.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

FirebaseApp.Create(new AppOptions
{
    Credential = GoogleCredential.FromFile(builder.Configuration["Firebase:CredentialsPath"]),
});

var app = builder.Build();

app.UseMiddleware<ApiExceptionMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

// Proteger /hangfire con autorización antes de exponerlo en producción —
// aquí queda accesible solo en desarrollo a modo de ejemplo.
if (app.Environment.IsDevelopment())
{
    app.UseHangfireDashboard("/hangfire");
}

app.MapControllers();

RecurringJob.AddOrUpdate<ReminderDispatchJob>(
    "dispatch-due-reminders", job => job.DispatchDueRemindersAsync(), "*/1 * * * *");
RecurringJob.AddOrUpdate<UnscheduledDigestJob>(
    "dispatch-unscheduled-digest", job => job.RunAsync(), Cron.Daily(8));

app.Run();
