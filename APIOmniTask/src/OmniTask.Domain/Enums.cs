namespace OmniTask.Domain;

// Los nombres de los miembros se mapean a las etiquetas de los ENUM de Postgres
// (schema.sql) vía Npgsql.MapEnum en Program.cs — "professional" <-> Professional.

public enum UserRole
{
    Admin,
    Professional,
    Assistant,
}

public enum DevicePlatform
{
    Ios,
    Android,
}

public enum ActivityType
{
    Meeting,
    Appointment,
    Task,
    Activity,
}

public enum ActivityStatus
{
    Unscheduled,
    Scheduled,
    Completed,
    Cancelled,
}

public enum ReminderChannel
{
    Push,
    Whatsapp,
    Both,
}

public enum ReminderStatus
{
    Pending,
    Processing,
    Sent,
    Failed,
}

public enum NotificationChannel
{
    Push,
    Whatsapp,
}

public enum NotificationStatus
{
    Queued,
    Sent,
    Delivered,
    Read,
    Failed,
}

public enum TemplateCategory
{
    Utility,
    Marketing,
    Authentication,
}

public enum TemplateApprovalStatus
{
    Pending,
    Approved,
    Rejected,
}
