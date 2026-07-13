using System.Text.Json;
using System.Text.Json.Nodes;
using OmniTask.Application.Dtos;

namespace OmniTask.Infrastructure.Services;

// La columna users.notification_preferences es JSONB con forma fija
// ({"default_channel": ..., "reminder_offsets_minutes": [...]}) — se
// serializa/parsea a mano en vez de arrastrar un tipo de entidad completo
// solo para dos campos (§16).
public static class NotificationPreferencesJson
{
    public static NotificationPreferencesDto Parse(string json)
    {
        var node = JsonNode.Parse(json)!;
        var offsets = node["reminder_offsets_minutes"]!.AsArray().Select(n => n!.GetValue<int>()).ToList();
        return new NotificationPreferencesDto(node["default_channel"]!.GetValue<string>(), offsets);
    }

    public static string Serialize(NotificationPreferencesDto preferences)
    {
        var node = new JsonObject
        {
            ["default_channel"] = preferences.DefaultChannel,
            ["reminder_offsets_minutes"] = new JsonArray(preferences.ReminderOffsetsMinutes.Select(m => JsonValue.Create(m)).ToArray()),
        };
        return node.ToJsonString();
    }
}
