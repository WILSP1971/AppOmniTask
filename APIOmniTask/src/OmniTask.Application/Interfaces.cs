using OmniTask.Application.Dtos;

namespace OmniTask.Application.Interfaces;

public interface IAuthService
{
    Task<RegisterResponse> RegisterAsync(RegisterRequest request);
    Task<TokenPairResponse> LoginAsync(LoginRequest request);
    Task<TokenPairResponse> RefreshAsync(string refreshToken);
    Task LogoutAsync(string refreshToken);
    Task<UserResponse> GetProfileAsync(Guid userId);
    Task<UserResponse> UpdateProfileAsync(Guid userId, UpdateProfileRequest request);
}

public interface IActivityService
{
    Task<ActivityResponse> CreateAsync(Guid userId, ActivityCreateRequest request);

    Task<PagedResponse<ActivityResponse>> ListAsync(
        Guid userId, DateTimeOffset? from, DateTimeOffset? to, string? type, string? status, int page, int limit);

    Task<List<ActivityResponse>> ListUnscheduledAsync(Guid userId);
    Task<ActivityResponse> GetByIdAsync(Guid userId, Guid activityId);
    Task<ActivityResponse> UpdateAsync(Guid userId, Guid activityId, ActivityUpdateRequest request);
    Task CancelAsync(Guid userId, Guid activityId);
}

public interface IContactService
{
    Task<ContactResponse> CreateAsync(Guid userId, ContactRequest request);
    Task<List<ContactResponse>> ListAsync(Guid userId, string? search);
    Task<ContactResponse> GetByIdAsync(Guid userId, Guid contactId);
    Task<ContactResponse> UpdateAsync(Guid userId, Guid contactId, ContactRequest request);
    Task DeleteAsync(Guid userId, Guid contactId);
}

public interface IDeviceService
{
    Task RegisterAsync(Guid userId, string fcmToken, string platform);
    Task<List<DeviceResponse>> ListAsync(Guid userId);
    Task DeleteAsync(Guid userId, Guid deviceId);
}

public interface INotificationService
{
    Task<PagedResponse<NotificationResponse>> ListAsync(Guid userId, bool unreadOnly, int page, int limit);
    Task<int> UnreadCountAsync(Guid userId);
    Task AcknowledgeAsync(Guid userId, Guid notificationId);
    Task AcknowledgeAllAsync(Guid userId);
}

// Implementada en Infrastructure (WhatsAppCloudApiClient) — llama a la Cloud API de Meta (§7).
public interface IWhatsAppClient
{
    Task<string> SendTemplateMessageAsync(
        string toE164, string templateName, string languageCode, IReadOnlyList<string> bodyParameters);
}

// Implementada en Infrastructure (FirebasePushSender) — Firebase Admin SDK (§8, §20).
public interface IPushSender
{
    Task SendAsync(string fcmToken, string title, string body, IDictionary<string, string> data);
}
