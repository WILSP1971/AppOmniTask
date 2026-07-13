using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using OmniTask.Application.Interfaces;

namespace OmniTask.Infrastructure.ExternalServices;

// Llama a la Cloud API de Meta directamente (§7, §21) — sin intermediario (BSP).
public class WhatsAppCloudApiClient : IWhatsAppClient
{
    private readonly HttpClient _http;
    private readonly IConfiguration _config;

    public WhatsAppCloudApiClient(HttpClient http, IConfiguration config)
    {
        _http = http;
        _config = config;
    }

    public async Task<string> SendTemplateMessageAsync(
        string toE164, string templateName, string languageCode, IReadOnlyList<string> bodyParameters)
    {
        var phoneNumberId = _config["WhatsApp:PhoneNumberId"];
        var payload = new
        {
            messaging_product = "whatsapp",
            to = toE164,
            type = "template",
            template = new
            {
                name = templateName,
                language = new { code = languageCode },
                components = new object[]
                {
                    new
                    {
                        type = "body",
                        parameters = bodyParameters.Select(p => new { type = "text", text = p }),
                    },
                },
            },
        };

        using var request = new HttpRequestMessage(
            HttpMethod.Post, $"https://graph.facebook.com/v20.0/{phoneNumberId}/messages")
        {
            Content = JsonContent.Create(payload),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _config["WhatsApp:AccessToken"]);

        var response = await _http.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        // El wamid se guarda en notification_log.provider_message_id (§7) para
        // cruzarlo después con el webhook de estado.
        return body.GetProperty("messages")[0].GetProperty("id").GetString()!;
    }
}
