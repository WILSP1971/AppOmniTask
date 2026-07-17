using OmniTask.Api;
using Xunit;

namespace OmniTask.Tests.Security;

public class Argon2PasswordHasherTests
{
    private readonly Argon2PasswordHasher _hasher = new();

    [Fact]
    public void Hash_produce_un_valor_distinto_del_password_en_texto_plano()
    {
        var hash = _hasher.Hash("una-contraseña-fuerte");

        Assert.NotEqual("una-contraseña-fuerte", hash);
        Assert.Contains(':', hash); // salt:hash (§10)
    }

    [Fact]
    public void Hash_no_es_determinista_por_la_sal_aleatoria()
    {
        var hash1 = _hasher.Hash("misma-contraseña");
        var hash2 = _hasher.Hash("misma-contraseña");

        Assert.NotEqual(hash1, hash2);
    }

    [Fact]
    public void Verify_acepta_el_password_correcto()
    {
        var hash = _hasher.Hash("correcta123");
        Assert.True(_hasher.Verify("correcta123", hash));
    }

    [Fact]
    public void Verify_rechaza_un_password_incorrecto()
    {
        var hash = _hasher.Hash("correcta123");
        Assert.False(_hasher.Verify("otra-cosa", hash));
    }
}
