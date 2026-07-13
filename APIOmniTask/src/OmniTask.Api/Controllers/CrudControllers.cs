using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;

namespace OmniTask.Api.Controllers;

[ApiController]
[Route("api/v1/contacts")]
[Authorize]
public class ContactsController : ControllerBase
{
    private readonly IContactService _contactService;

    public ContactsController(IContactService contactService) => _contactService = contactService;

    [HttpPost]
    public async Task<IActionResult> Create(ContactRequest request)
    {
        var contact = await _contactService.CreateAsync(User.GetUserId(), request);
        return CreatedAtAction(nameof(GetById), new { id = contact.Id }, contact);
    }

    [HttpGet]
    public async Task<ActionResult<List<ContactResponse>>> List([FromQuery] string? search) =>
        Ok(await _contactService.ListAsync(User.GetUserId(), search));

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ContactResponse>> GetById(Guid id) =>
        Ok(await _contactService.GetByIdAsync(User.GetUserId(), id));

    [HttpPatch("{id:guid}")]
    public async Task<ActionResult<ContactResponse>> Update(Guid id, ContactRequest request) =>
        Ok(await _contactService.UpdateAsync(User.GetUserId(), id, request));

    // 409 si tiene actividades asociadas (§6) — evita dejar huérfanos los
    // mensajes ya registrados en notification_log.
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        await _contactService.DeleteAsync(User.GetUserId(), id);
        return NoContent();
    }
}

[ApiController]
[Route("api/v1/devices")]
[Authorize]
public class DevicesController : ControllerBase
{
    private readonly IDeviceService _deviceService;

    public DevicesController(IDeviceService deviceService) => _deviceService = deviceService;

    [HttpPost]
    public async Task<IActionResult> Register(RegisterDeviceRequest request)
    {
        await _deviceService.RegisterAsync(User.GetUserId(), request.FcmToken, request.Platform);
        return NoContent();
    }

    [HttpGet]
    public async Task<ActionResult<List<DeviceResponse>>> List() =>
        Ok(await _deviceService.ListAsync(User.GetUserId()));

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        await _deviceService.DeleteAsync(User.GetUserId(), id);
        return NoContent();
    }
}
