using OmniTask.Application;

namespace OmniTask.Infrastructure.Services;

// Enum.Parse crudo lanza FormatException ante un valor inválido — no es una
// ApiException, así que ApiExceptionMiddleware no la atrapa y el cliente
// recibe un 500 en vez de un 422 claro (ej. {"type": "no_existe"}).
public static class EnumParsing
{
    public static TEnum Parse<TEnum>(string value, string fieldName) where TEnum : struct, Enum
    {
        if (Enum.TryParse<TEnum>(value, ignoreCase: true, out var parsed) && Enum.IsDefined(parsed))
            return parsed;

        throw new ApiException(422, "invalid_value", $"Valor inválido para '{fieldName}': {value}");
    }
}
