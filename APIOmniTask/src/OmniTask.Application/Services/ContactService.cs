using Microsoft.EntityFrameworkCore;
using OmniTask.Application.Dtos;
using OmniTask.Application.Interfaces;
using OmniTask.Domain.Entities;

namespace OmniTask.Application.Services;

public class ContactService : IContactService
{
    private readonly DbContext _db;
    private readonly DbSet<Contact> _contacts;

    public ContactService(DbContext db)
    {
        _db = db;
        _contacts = db.Set<Contact>();
    }

    public async Task<ContactResponse> CreateAsync(Guid userId, ContactRequest request)
    {
        var contact = new Contact
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            FullName = request.FullName,
            PhoneE164 = request.PhoneE164,
            Notes = request.Notes,
        };
        _contacts.Add(contact);
        await _db.SaveChangesAsync();
        return ToResponse(contact);
    }

    public async Task<List<ContactResponse>> ListAsync(Guid userId, string? search)
    {
        var query = _contacts.Where(c => c.UserId == userId);
        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(c => EF.Functions.ILike(c.FullName, $"%{search}%"));

        return await query.OrderBy(c => c.FullName)
            .Select(c => new ContactResponse(c.Id, c.FullName, c.PhoneE164, c.Notes))
            .ToListAsync();
    }

    public async Task<ContactResponse> GetByIdAsync(Guid userId, Guid contactId)
    {
        var contact = await _contacts.SingleOrDefaultAsync(c => c.Id == contactId && c.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Contacto no encontrado");
        return ToResponse(contact);
    }

    public async Task<ContactResponse> UpdateAsync(Guid userId, Guid contactId, ContactRequest request)
    {
        var contact = await _contacts.SingleOrDefaultAsync(c => c.Id == contactId && c.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Contacto no encontrado");

        contact.FullName = request.FullName;
        contact.PhoneE164 = request.PhoneE164;
        contact.Notes = request.Notes;
        await _db.SaveChangesAsync();
        return ToResponse(contact);
    }

    public async Task DeleteAsync(Guid userId, Guid contactId)
    {
        var contact = await _contacts.Include(c => c.Activities)
            .SingleOrDefaultAsync(c => c.Id == contactId && c.UserId == userId)
            ?? throw new ApiException(404, "not_found", "Contacto no encontrado");

        if (contact.Activities.Count > 0)
            throw new ApiException(409, "contact_in_use", "Este contacto tiene actividades asociadas");

        _contacts.Remove(contact);
        await _db.SaveChangesAsync();
    }

    private static ContactResponse ToResponse(Contact c) => new(c.Id, c.FullName, c.PhoneE164, c.Notes);
}
