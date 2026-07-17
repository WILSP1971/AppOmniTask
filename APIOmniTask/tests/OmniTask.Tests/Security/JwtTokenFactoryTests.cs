using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Configuration;
using OmniTask.Api;
using OmniTask.Application;
using Xunit;

namespace OmniTask.Tests.Security;

public class JwtTokenFactoryTests
{
    private readonly JwtTokenFactory _factory;

    public JwtTokenFactoryTests()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Secret"] = "clave-de-prueba-de-al-menos-32-bytes!!",
            })
            .Build();
        _factory = new JwtTokenFactory(config);
    }

    [Fact]
    public void CreateAccessToken_incluye_el_claim_type_access_y_el_sub_correcto()
    {
        var userId = Guid.NewGuid();
        var token = _factory.CreateAccessToken(userId);

        var claims = new JwtSecurityTokenHandler().ReadJwtToken(token).Claims.ToList();
        Assert.Equal("access", claims.Single(c => c.Type == "type").Value);
        Assert.Equal(userId.ToString(), claims.Single(c => c.Type == JwtRegisteredClaimNames.Sub).Value);
    }

    [Fact]
    public void CreateRefreshToken_expira_en_aproximadamente_30_días_y_tiene_jti_propio()
    {
        var (token, jti, expiresAt) = _factory.CreateRefreshToken(Guid.NewGuid());

        var claims = new JwtSecurityTokenHandler().ReadJwtToken(token).Claims.ToList();
        Assert.Equal(jti.ToString(), claims.Single(c => c.Type == JwtRegisteredClaimNames.Jti).Value);
        Assert.Equal("refresh", claims.Single(c => c.Type == "type").Value);
        Assert.InRange(expiresAt, DateTimeOffset.UtcNow.AddDays(29), DateTimeOffset.UtcNow.AddDays(31));
    }

    [Fact]
    public void ReadRefreshJti_devuelve_el_mismo_jti_que_se_emitió()
    {
        var (token, jti, _) = _factory.CreateRefreshToken(Guid.NewGuid());
        Assert.Equal(jti, _factory.ReadRefreshJti(token));
    }

    // Un access token nunca debe servir para lo que espera un refresh (§10) —
    // aquí es donde ReadRefreshJti tiene que rechazarlo, no en el llamador.
    [Fact]
    public void ReadRefreshJti_rechaza_un_access_token()
    {
        var accessToken = _factory.CreateAccessToken(Guid.NewGuid());

        var ex = Assert.Throws<ApiException>(() => _factory.ReadRefreshJti(accessToken));
        Assert.Equal(401, ex.StatusCode);
    }

    [Fact]
    public void ReadRefreshJti_rechaza_un_token_manipulado()
    {
        var (token, _, _) = _factory.CreateRefreshToken(Guid.NewGuid());
        var tampered = token[..^2] + "xx";

        var ex = Assert.Throws<ApiException>(() => _factory.ReadRefreshJti(tampered));
        Assert.Equal(401, ex.StatusCode);
    }
}
