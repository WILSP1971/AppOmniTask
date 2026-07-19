namespace OmniTask.Application.Dtos;

// ---- Común ----

public record PagedResponse<T>(List<T> Items, int Page, int Limit, int Total);

// ---- Auth (§6, §10, §16) ----

public record RegisterRequest(string FullName, string Email, string Password, string PhoneE164, string Timezone);

public record LoginRequest(string Email, string Password);

public record RefreshRequest(string RefreshToken);

public record TokenPairResponse(string AccessToken, string RefreshToken);

public record NotificationPreferencesDto(string DefaultChannel, List<int> ReminderOffsetsMinutes);

public record UserResponse(
    Guid Id,
    string FullName,
    string Email,
    string PhoneE164,
    string Timezone,
    string Role,
    NotificationPreferencesDto NotificationPreferences);

public record RegisterResponse(UserResponse User, string AccessToken, string RefreshToken);

public record UpdateProfileRequest(
    string? FullName,
    string? PhoneE164,
    string? Timezone,
    NotificationPreferencesDto? NotificationPreferences);

// ---- Activities (§6, §9) ----

public record ActivityCreateRequest(
    string Type,
    string Title,
    string? Description,
    Guid? ContactId,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    string? Location,
    // SPEC-003 (§6, §3 RF1): link de reunión pegado manualmente; ambos nulos
    // si la actividad no tiene reunión.
    string? MeetingUrl = null,
    string? MeetingProvider = null);

// ClearStartsAt/ClearEndsAt existen porque un valor null en StartsAt/EndsAt es
// ambiguo por sí solo ("no lo toques" vs. "bórralo") — con el flag explícito,
// el cliente puede pedir "quitar la fecha" (devolver la actividad al backlog)
// sin que un simple omitir el campo tenga el mismo efecto por accidente.
public record ActivityUpdateRequest(
    string? Title,
    string? Description,
    DateTimeOffset? StartsAt,
    bool ClearStartsAt = false,
    DateTimeOffset? EndsAt = null,
    bool ClearEndsAt = false,
    string? Status = null,
    string? Location = null,
    // SPEC-003 (§6, §3 RF2): mismo criterio "NULL = no lo toques" que
    // Title/Description/Location — no hay flag de "limpiar" porque no fue
    // pedido por la SPEC.
    string? MeetingUrl = null,
    string? MeetingProvider = null);

public record ReminderSummaryResponse(Guid Id, DateTimeOffset RemindAt, string Channel, string Status);

public record ActivityResponse(
    Guid Id,
    Guid UserId,
    Guid? ContactId,
    string Type,
    string Title,
    string? Description,
    string Status,
    DateTimeOffset? StartsAt,
    DateTimeOffset? EndsAt,
    string Timezone,
    string? Location,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    string? MeetingUrl = null,
    string? MeetingProvider = null,
    List<ReminderSummaryResponse>? Reminders = null);

// ---- Activity attachments (SPEC-002, §6) ----

public record AttachmentResponse(
    Guid Id,
    Guid ActivityId,
    string FileName,
    string ContentType,
    long SizeBytes,
    DateTimeOffset UploadedAt);

// ---- Contacts (§6) ----

public record ContactRequest(string FullName, string PhoneE164, string? Notes);

public record ContactResponse(Guid Id, string FullName, string PhoneE164, string? Notes);

// ---- Devices (§8) ----

public record RegisterDeviceRequest(string FcmToken, string Platform);

public record DeviceResponse(Guid Id, string FcmToken, string Platform, DateTimeOffset LastSeenAt);

// ---- Notifications (§17) ----

public record NotificationResponse(
    Guid Id,
    string Channel,
    string Status,
    string Summary,
    Guid? ActivityId,
    DateTimeOffset CreatedAt,
    DateTimeOffset? AcknowledgedAt);
