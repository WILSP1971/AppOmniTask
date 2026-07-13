using FirebaseAdmin.Messaging;
using OmniTask.Application.Interfaces;

namespace OmniTask.Infrastructure.ExternalServices;

// Requiere que Program.cs haya llamado a FirebaseApp.Create(...) una sola vez
// al arrancar, con la credencial de servicio del §20.
public class FirebasePushSender : IPushSender
{
    public async Task SendAsync(string fcmToken, string title, string body, IDictionary<string, string> data)
    {
        var message = new Message
        {
            Token = fcmToken,
            Notification = new Notification { Title = title, Body = body },
            Data = data,
        };

        try
        {
            await FirebaseMessaging.DefaultInstance.SendAsync(message);
        }
        catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
        {
            // El token venció o la app se desinstaló — se limpia desde el llamador
            // (ReminderDispatchJob), que sí tiene acceso al DbContext para borrar el device.
            throw;
        }
    }
}
