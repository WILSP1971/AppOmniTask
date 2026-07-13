namespace OmniTask.Domain.Entities;

using OmniTask.Domain;

public class Activity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid? ContactId { get; set; }
    public ActivityType Type { get; set; }
    public string Title { get; set; } = default!;
    public string? Description { get; set; }
    public ActivityStatus Status { get; set; } = ActivityStatus.Scheduled;

    // NULL = "sin fecha de calendario" (§3/§6) — estado de primera clase, no una omisión.
    public DateTimeOffset? StartsAt { get; set; }
    public DateTimeOffset? EndsAt { get; set; }
    public string Timezone { get; set; } = default!;
    public string? Location { get; set; }
    public int? NudgeFrequencyDays { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = default!;
    public Contact? Contact { get; set; }
    public ICollection<Reminder> Reminders { get; set; } = new List<Reminder>();
}

public class Reminder
{
    public Guid Id { get; set; }
    public Guid ActivityId { get; set; }
    public DateTimeOffset RemindAt { get; set; }
    public ReminderChannel Channel { get; set; }
    public Guid? TemplateId { get; set; }
    public ReminderStatus Status { get; set; } = ReminderStatus.Pending;
    public DateTimeOffset? SentAt { get; set; }

    public Activity Activity { get; set; } = default!;
}

public class NotificationLog
{
    public Guid Id { get; set; }
    public Guid? ReminderId { get; set; }
    public Guid UserId { get; set; }
    public NotificationChannel Channel { get; set; }
    public string? ProviderMessageId { get; set; }
    public NotificationStatus Status { get; set; } = NotificationStatus.Queued;

    // Texto tal como se envió, capturado en el momento (§17) — no depende de
    // que la actividad siga existiendo o sin cambios más adelante.
    public string Summary { get; set; } = default!;
    public string? ErrorDetail { get; set; }

    // Distinto de Status: si la persona ya lo vio en la bandeja de la app,
    // no si Meta reporta el WhatsApp como entregado/leído (§17).
    public DateTimeOffset? AcknowledgedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public Reminder? Reminder { get; set; }
}
