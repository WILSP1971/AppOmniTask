namespace OmniTask.Application;

// La capa Api la atrapa en un middleware y la traduce al sobre
// {"error": {"code": "...", "message": "..."}} de la convención de la §6.
public class ApiException : Exception
{
    public int StatusCode { get; }
    public string Code { get; }

    public ApiException(int statusCode, string code, string message) : base(message)
    {
        StatusCode = statusCode;
        Code = code;
    }
}
