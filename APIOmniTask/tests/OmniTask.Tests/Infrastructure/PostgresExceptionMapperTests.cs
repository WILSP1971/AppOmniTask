using Npgsql;
using OmniTask.Infrastructure.Services;
using Xunit;

namespace OmniTask.Tests.Infrastructure;

// Los códigos SQLSTATE personalizados de db/03_stored_procedures_and_functions.sql
// (§23) son el contrato entre el SQL y esta traducción — si alguno cambia de un
// lado sin el otro, este archivo es lo primero que debería fallar.
public class PostgresExceptionMapperTests
{
    private static PostgresException Build(string sqlState, string message) =>
        new(message, "ERROR", "ERROR", sqlState);

    [Fact]
    public void OT001_se_traduce_a_404()
    {
        var mapped = PostgresExceptionMapper.TryMap(Build("OT001", "Actividad no encontrada"));

        Assert.NotNull(mapped);
        Assert.Equal(404, mapped!.StatusCode);
        Assert.Equal("Actividad no encontrada", mapped.Message);
    }

    [Fact]
    public void OT002_se_traduce_a_409()
    {
        var mapped = PostgresExceptionMapper.TryMap(Build("OT002", "Ya existe una cuenta con ese correo."));
        Assert.NotNull(mapped);
        Assert.Equal(409, mapped!.StatusCode);
    }

    [Fact]
    public void OT003_se_traduce_a_422()
    {
        var mapped = PostgresExceptionMapper.TryMap(Build("OT003", "ends_at debe ser posterior a starts_at"));
        Assert.NotNull(mapped);
        Assert.Equal(422, mapped!.StatusCode);
    }

    [Fact]
    public void un_sqlstate_no_reconocido_no_se_mapea()
    {
        // SqlServiceBase relanza la PostgresException original cuando esto
        // devuelve null — un error de Postgres genuinamente inesperado no
        // debe disfrazarse de un 404/409/422 que no le corresponde.
        var mapped = PostgresExceptionMapper.TryMap(Build("23505", "unique_violation sin código propio"));
        Assert.Null(mapped);
    }
}
