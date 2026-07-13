using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api.Controllers;

[ApiController]
[Route("api/v1/auth")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;

    public AuthController(IAuthService authService) => _authService = authService;

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register(RegisterRequest request)
    {
        var response = await _authService.RegisterAsync(request);
        return StatusCode(201, response);
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<TokenPairResponse>> Login(LoginRequest request) =>
        Ok(await _authService.LoginAsync(request));

    [HttpPost("refresh")]
    [AllowAnonymous]
    public async Task<ActionResult<TokenPairResponse>> Refresh(RefreshRequest request) =>
        Ok(await _authService.RefreshAsync(request.RefreshToken));

    [HttpPost("logout")]
    [Authorize]
    public async Task<IActionResult> Logout(RefreshRequest request)
    {
        await _authService.LogoutAsync(request.RefreshToken);
        return Ok(new { detail = "Sesión cerrada" });
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<ActionResult<UserResponse>> Me() =>
        Ok(await _authService.GetProfileAsync(User.GetUserId()));

    [HttpPatch("me")]
    [Authorize]
    public async Task<ActionResult<UserResponse>> UpdateMe(UpdateProfileRequest request) =>
        Ok(await _authService.UpdateProfileAsync(User.GetUserId(), request));
}
