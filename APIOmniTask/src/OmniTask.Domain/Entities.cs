namespace OmniTask.Domain.Entities;

using OmniTask.Domain;

// Mapea a la columna JSONB users.notification_preferences (§16) vía
// OwnsOne(...).ToJson() en OmniTaskDbContext — sin tabla propia.
public class NotificationPreferences
{
    public string DefaultChannel { get; set; } = "both";
    public List<int> ReminderOffsetsMinutes { get; set; } = new() { 1440, 60 };
}

public class User
{
    public Guid Id { get; set; }
    public string FullName { get; set; } = default!;
    public string Email { get; set; } = default!;
    public string PasswordHash { get; set; } = default!;
    public string PhoneE164 { get; set; } = default!;
    public string Timezone { get; set; } = default!;
    public UserRole Role { get; set; } = UserRole.Professional;
    public NotificationPreferences NotificationPreferences { get; set; } = new();
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Contact> Contacts { get; set; } = new List<Contact>();
    public ICollection<Activity> Activities { get; set; } = new List<Activity>();
    public ICollection<Device> Devices { get; set; } = new List<Device>();
}

public class Contact
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string FullName { get; set; } = default!;
    public string PhoneE164 { get; set; } = default!;
    public string? Notes { get; set; }

    public User User { get; set; } = default!;
    public ICollection<Activity> Activities { get; set; } = new List<Activity>();
}

public class Device
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string FcmToken { get; set; } = default!;
    public DevicePlatform Platform { get; set; }
    public DateTimeOffset LastSeenAt { get; set; }

    public User User { get; set; } = default!;
}

public class WhatsAppTemplate
{
    public Guid Id { get; set; }
    public string MetaTemplateName { get; set; } = default!;
    public string LanguageCode { get; set; } = default!;
    public TemplateCategory Category { get; set; }
    public TemplateApprovalStatus ApprovalStatus { get; set; } = TemplateApprovalStatus.Pending;
    public Dictionary<string, object> VariablesSchema { get; set; } = new();
}

// Reemplaza el store de Redis del diseño original en Python (§10) — un solo
// motor de datos (Postgres) para todo en el servidor Windows/IIS (§18).
public class RefreshToken
{
    public Guid Jti { get; set; }
    public Guid UserId { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }

    public User User { get; set; } = default!;
}
