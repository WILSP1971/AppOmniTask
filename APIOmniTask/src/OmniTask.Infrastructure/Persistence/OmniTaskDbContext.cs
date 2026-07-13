using Microsoft.EntityFrameworkCore;
using OmniTask.Domain.Entities;

namespace OmniTask.Infrastructure.Persistence;

// Mapea 1:1 contra las tablas ya creadas por db/schema.sql — no genera
// migraciones de EF Core sobre una base que ya existe en producción (§18).
public class OmniTaskDbContext : DbContext
{
    public OmniTaskDbContext(DbContextOptions<OmniTaskDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Contact> Contacts => Set<Contact>();
    public DbSet<Activity> Activities => Set<Activity>();
    public DbSet<Reminder> Reminders => Set<Reminder>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<NotificationLog> NotificationLogs => Set<NotificationLog>();
    public DbSet<WhatsAppTemplate> WhatsAppTemplates => Set<WhatsAppTemplate>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasIndex(u => u.Email).IsUnique();
            entity.OwnsOne(u => u.NotificationPreferences, nav => nav.ToJson());
        });

        modelBuilder.Entity<Contact>(entity =>
        {
            entity.HasOne(c => c.User).WithMany(u => u.Contacts).HasForeignKey(c => c.UserId);
        });

        modelBuilder.Entity<Device>(entity =>
        {
            entity.HasIndex(d => d.FcmToken).IsUnique();
            entity.HasOne(d => d.User).WithMany(u => u.Devices).HasForeignKey(d => d.UserId);
        });

        modelBuilder.Entity<Activity>(entity =>
        {
            entity.HasOne(a => a.User).WithMany(u => u.Activities).HasForeignKey(a => a.UserId);
            entity.HasOne(a => a.Contact).WithMany(c => c.Activities)
                .HasForeignKey(a => a.ContactId).OnDelete(DeleteBehavior.SetNull);
            entity.HasIndex(a => a.StartsAt);
            // La bandeja de "pendientes por programar" (§4/§12) filtra por esto constantemente.
            entity.HasIndex(a => a.UserId).HasFilter("starts_at IS NULL");
            entity.ToTable(t => t.HasCheckConstraint(
                "chk_ends_after_starts", "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at"));
        });

        modelBuilder.Entity<Reminder>(entity =>
        {
            entity.HasOne(r => r.Activity).WithMany(a => a.Reminders)
                .HasForeignKey(r => r.ActivityId).OnDelete(DeleteBehavior.Cascade);
            // El índice que hace barato el SELECT ... FOR UPDATE SKIP LOCKED de la §8.
            entity.HasIndex(r => r.RemindAt).HasFilter("status = 'pending'");
        });

        modelBuilder.Entity<NotificationLog>(entity =>
        {
            // El nombre de tabla original (§3) es singular, distinto del plural
            // convencional que produciría el DbSet "NotificationLogs".
            entity.ToTable("notification_log");
            entity.HasOne(n => n.Reminder).WithMany()
                .HasForeignKey(n => n.ReminderId).OnDelete(DeleteBehavior.SetNull);
            entity.HasIndex(n => new { n.UserId, n.CreatedAt });
            // Alimenta /notifications/unread-count (§17) sin escanear toda la tabla.
            entity.HasIndex(n => n.UserId).HasFilter("acknowledged_at IS NULL");
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasKey(t => t.Jti);
            entity.HasOne(t => t.User).WithMany().HasForeignKey(t => t.UserId).OnDelete(DeleteBehavior.Cascade);
            entity.HasIndex(t => t.UserId);
        });
    }
}
