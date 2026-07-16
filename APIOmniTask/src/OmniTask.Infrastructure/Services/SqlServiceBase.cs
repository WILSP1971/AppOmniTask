using Npgsql;
using OmniTask.Application;

namespace OmniTask.Infrastructure.Services;

// Traduce los SQLSTATE personalizados de db/03_stored_procedures_and_functions.sql
// a ApiException — así los controladores no necesitan saber que el error vino
// de un RAISE EXCEPTION en PostgreSQL.
public static class PostgresExceptionMapper
{
    public static ApiException? TryMap(PostgresException ex) => ex.SqlState switch
    {
        "OT001" => new ApiException(404, "not_found", ex.MessageText),
        "OT002" => new ApiException(409, "conflict", ex.MessageText),
        "OT003" => new ApiException(422, "invalid", ex.MessageText),
        _ => null,
    };
}

// Punto único donde cada servicio abre una conexión, corre su función/
// procedimiento y traduce errores — evita repetir el mismo try/catch en
// cada uno de los ~20 métodos que llaman a la base.
public abstract class SqlServiceBase
{
    protected readonly NpgsqlDataSource DataSource;

    protected SqlServiceBase(NpgsqlDataSource dataSource) => DataSource = dataSource;

    protected async Task RunAsync(Func<NpgsqlConnection, Task> action)
    {
        await using var conn = await DataSource.OpenConnectionAsync();
        try
        {
            await action(conn);
        }
        catch (PostgresException ex)
        {
            var mapped = PostgresExceptionMapper.TryMap(ex);
            if (mapped is not null) throw mapped;
            throw;
        }
    }

    protected async Task<T> RunAsync<T>(Func<NpgsqlConnection, Task<T>> action)
    {
        await using var conn = await DataSource.OpenConnectionAsync();
        try
        {
            return await action(conn);
        }
        catch (PostgresException ex)
        {
            var mapped = PostgresExceptionMapper.TryMap(ex);
            if (mapped is not null) throw mapped;
            throw;
        }
    }
}
