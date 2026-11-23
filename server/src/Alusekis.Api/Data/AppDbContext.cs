using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Session> Sessions => Set<Session>();
    public DbSet<City> Cities => Set<City>();
    public DbSet<Store> Stores => Set<Store>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<PriceEntry> PriceEntries => Set<PriceEntry>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<AuditEntry> AuditEntries => Set<AuditEntry>();
    public DbSet<RequestResult> RequestResults => Set<RequestResult>();
    public DbSet<DeletionMarker> DeletionMarkers => Set<DeletionMarker>();

    /// <summary>The only <see cref="PriceEntry"/> column that may change after insert.</summary>
    internal const string MutablePriceEntryProperty = nameof(PriceEntry.Status);

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
    {
        // All timestamps are UTC; SQLite has no time zone so Kind is restored on read.
        configurationBuilder.Properties<DateTime>().HaveConversion<UtcDateTimeConverter>();
        configurationBuilder.Properties<DateTime?>().HaveConversion<UtcDateTimeConverter>();
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(e =>
        {
            e.Property(x => x.Email).HasMaxLength(254);
            e.Property(x => x.NormalizedEmail).HasMaxLength(254);
            e.Property(x => x.DisplayName).HasMaxLength(100);
            e.Property(x => x.PasswordHash).HasMaxLength(256);
            e.Property(x => x.PasswordResetTokenHash).HasMaxLength(128);
            e.HasIndex(x => x.NormalizedEmail).IsUnique();
            e.HasIndex(x => x.PasswordResetTokenHash).IsUnique();
            e.ToTable(t => t.HasCheckConstraint("CK_Users_Role", EnumCheck<Role>(nameof(User.Role))));
        });

        modelBuilder.Entity<Session>(e =>
        {
            e.Property(x => x.TokenHash).HasMaxLength(128);
            e.HasIndex(x => x.TokenHash).IsUnique();
            e.HasOne(x => x.User).WithMany(x => x.Sessions)
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<City>(e =>
        {
            e.Property(x => x.Name).HasMaxLength(100);
            e.Property(x => x.NormalizedName).HasMaxLength(100);
            e.HasIndex(x => x.NormalizedName).IsUnique();
        });

        modelBuilder.Entity<Store>(e =>
        {
            e.Property(x => x.Name).HasMaxLength(150);
            e.Property(x => x.Address).HasMaxLength(250);
            e.HasIndex(x => new { x.CityId, x.Name, x.Address }).IsUnique();
            e.HasOne(x => x.City).WithMany(x => x.Stores)
                .HasForeignKey(x => x.CityId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Product>(e =>
        {
            e.Property(x => x.Name).HasMaxLength(150);
            e.Property(x => x.NormalizedName).HasMaxLength(150);
            e.Property(x => x.Brand).HasMaxLength(100);
            e.HasIndex(x => new { x.NormalizedName, x.VolumeMl }).IsUnique();
            e.HasOne(x => x.CreatedBy).WithMany()
                .HasForeignKey(x => x.CreatedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.ToTable(t => t.HasCheckConstraint(
                "CK_Products_VolumeMl",
                $"\"VolumeMl\" BETWEEN {DomainLimits.MinVolumeMl} AND {DomainLimits.MaxVolumeMl}"));
        });

        modelBuilder.Entity<PriceEntry>(e =>
        {
            // Serves "latest approved price of product X in store Y" and history queries.
            e.HasIndex(x => new { x.ProductId, x.StoreId, x.Status, x.ObservedAt, x.Id })
                .HasDatabaseName("IX_PriceEntries_Product_Store_Status_ObservedAt_Id");
            e.HasOne(x => x.Product).WithMany(x => x.PriceEntries)
                .HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Store).WithMany(x => x.PriceEntries)
                .HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.SubmittedBy).WithMany()
                .HasForeignKey(x => x.SubmittedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.ToTable(t =>
            {
                t.HasCheckConstraint(
                    "CK_PriceEntries_PriceCents",
                    $"\"PriceCents\" BETWEEN {DomainLimits.MinPriceCents} AND {DomainLimits.MaxPriceCents}");
                t.HasCheckConstraint("CK_PriceEntries_Status", EnumCheck<PriceStatus>(nameof(PriceEntry.Status)));
            });
        });

        modelBuilder.Entity<Report>(e =>
        {
            e.Property(x => x.Comment).HasMaxLength(1000);
            e.HasIndex(x => new { x.Status, x.SubmittedAt });
            e.HasOne(x => x.PriceEntry).WithMany()
                .HasForeignKey(x => x.PriceEntryId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Reporter).WithMany()
                .HasForeignKey(x => x.ReporterUserId).OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.ResolvedBy).WithMany()
                .HasForeignKey(x => x.ResolvedByUserId).OnDelete(DeleteBehavior.Restrict);
            e.ToTable(t =>
            {
                t.HasCheckConstraint("CK_Reports_Reason", EnumCheck<ReportReason>(nameof(Report.Reason)));
                t.HasCheckConstraint("CK_Reports_Status", EnumCheck<ReportStatus>(nameof(Report.Status)));
            });
        });

        modelBuilder.Entity<AuditEntry>(e =>
        {
            e.Property(x => x.Action).HasMaxLength(100);
            e.Property(x => x.EntityType).HasMaxLength(100);
            e.HasIndex(x => new { x.EntityType, x.EntityId });
            e.HasIndex(x => x.CreatedAt);
            e.HasOne(x => x.ActorUser).WithMany()
                .HasForeignKey(x => x.ActorUserId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<RequestResult>(e =>
        {
            e.Property(x => x.IdempotencyKey).HasMaxLength(100);
            e.HasIndex(x => new { x.UserId, x.IdempotencyKey }).IsUnique();
            e.HasIndex(x => x.CreatedAt);
            e.HasOne(x => x.User).WithMany()
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<DeletionMarker>(e =>
        {
            e.Property(x => x.EntityType).HasMaxLength(100);
            e.HasIndex(x => new { x.DeletedAt, x.Id });
            e.HasIndex(x => new { x.EntityType, x.EntityId });
        });
    }

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        EnforcePriceHistoryImmutability();
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        EnforcePriceHistoryImmutability();
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    private void EnforcePriceHistoryImmutability()
    {
        foreach (var entry in ChangeTracker.Entries<PriceEntry>())
        {
            if (entry.State == EntityState.Deleted)
            {
                throw new PriceHistoryImmutableException(
                    $"PriceEntry {entry.Entity.Id} cannot be deleted; price history is append-only.");
            }

            if (entry.State != EntityState.Modified)
            {
                continue;
            }

            var changed = entry.Properties
                .Where(p => p.IsModified && p.Metadata.Name != MutablePriceEntryProperty && !IsSubmitterAnonymization(p))
                .Select(p => p.Metadata.Name)
                .ToList();

            if (changed.Count > 0)
            {
                throw new PriceHistoryImmutableException(
                    $"PriceEntry {entry.Entity.Id} cannot be modified ({string.Join(", ", changed)}); " +
                    "record a new PriceEntry instead.");
            }
        }
    }

    /// <summary>Clearing the submitter (account deletion) is the only allowed change to that column.</summary>
    private static bool IsSubmitterAnonymization(Microsoft.EntityFrameworkCore.ChangeTracking.PropertyEntry property) =>
        property.Metadata.Name == nameof(PriceEntry.SubmittedByUserId) && property.CurrentValue is null;

    private static string EnumCheck<TEnum>(string column) where TEnum : struct, Enum =>
        $"\"{column}\" IN ({string.Join(", ", Enum.GetValues<TEnum>().Select(v => Convert.ToInt32(v)))})";
}
