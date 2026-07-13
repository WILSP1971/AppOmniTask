using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using OmniTask.Domain;

namespace OmniTask.Api.Controllers;

// Un solo endpoint público para verificación, estados de entrega y mensajes
// entrantes (§7) — la firma X-Hub-Signature-256 se valida antes de procesar
// cualquier POST, para que nadie pueda inyectar estados falsos adivinando la URL.
[ApiController]
[Route("webhooks/whatsapp")]
[AllowAnonymous]
public class WhatsAppWebhookController : ControllerBase
{
    private readonly IConfiguration _config;
    private readonly NpgsqlDataSource _dataSource;

    public WhatsAppWebhookController(IConfiguration config, NpgsqlDataSource dataSource)
    {
        _config = config;
        _dataSource = dataSource;
    }

    [HttpGet]
    public IActionResult Verify(
        [FromQuery(Name = "hub.mode")] string mode,
        [FromQuery(Name = "hub.verify_token")] string verifyToken,
        [FromQuery(Name = "hub.challenge")] string challenge)
    {
        if (mode == "subscribe" && verifyToken == _config["WhatsApp:WebhookVerifyToken"])
            return Content(challenge, "text/plain");

        return Forbid();
    }

    [HttpPost]
    public async Task<IActionResult> Receive()
    {
        Request.EnableBuffering();
        using var reader = new StreamReader(Request.Body, leaveOpen: true);
        var rawBody = await reader.ReadToEndAsync();
        Request.Body.Position = 0;

        if (!IsValidSignature(rawBody, Request.Headers["X-Hub-Signature-256"]))
            return Unauthorized();

        var payload = JsonSerializer.Deserialize<JsonElement>(rawBody);
        await ProcessAsync(payload);
        return Ok();
    }

    private bool IsValidSignature(string rawBody, string? headerValue)
    {
        if (string.IsNullOrEmpty(headerValue)) return false;

        var appSecret = _config["WhatsApp:AppSecret"]!;
        var computed = HMACSHA256.HashData(Encoding.UTF8.GetBytes(appSecret), Encoding.UTF8.GetBytes(rawBody));
        var expected = "sha256=" + Convert.ToHexString(computed).ToLowerInvariant();

        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(headerValue));
    }

    private async Task ProcessAsync(JsonElement payload)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        foreach (var entry in payload.GetProperty("entry").EnumerateArray())
        {
            foreach (var change in entry.GetProperty("changes").EnumerateArray())
            {
                var value = change.GetProperty("value");

                if (value.TryGetProperty("statuses", out var statuses))
                {
                    foreach (var status in statuses.EnumerateArray())
                        await UpdateDeliveryStatusAsync(conn, status);
                }

                // Mensajes entrantes (respuestas del contacto): se registran para que el
                // dueño de la actividad las vea, sin bot conversacional en este alcance (§7).
                if (value.TryGetProperty("messages", out var messages))
                {
                    foreach (var message in messages.EnumerateArray())
                        await LogInboundMessageAsync(message);
                }
            }
        }
    }

    private static async Task UpdateDeliveryStatusAsync(NpgsqlConnection conn, JsonElement status)
    {
        var wamid = status.GetProperty("id").GetString();
        var newStatus = status.GetProperty("status").GetString() switch
        {
            "sent" => NotificationStatus.Sent,
            "delivered" => NotificationStatus.Delivered,
            "read" => NotificationStatus.Read,
            "failed" => NotificationStatus.Failed,
            _ => (NotificationStatus?)null,
        };
        if (newStatus is null) return;

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "CALL sp_update_notification_delivery_status(@provider_message_id, @status)";
        cmd.Parameters.AddWithValue("provider_message_id", wamid!);
        cmd.Parameters.AddWithValue("status", newStatus.Value);
        await cmd.ExecuteNonQueryAsync();
    }

    private Task LogInboundMessageAsync(JsonElement message)
    {
        // Detalle de implementación real: resolver el contacto por número de
        // teléfono y notificar al usuario dueño de la actividad más reciente.
        return Task.CompletedTask;
    }
}
