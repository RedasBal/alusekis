using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Seeding;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class DataIntegrityTests : IDisposable
{
    private readonly TestDatabase _database = new();

    public DataIntegrityTests()
    {
        using var db = _database.CreateContext();
        new DataSeeder(db).SeedAsync().GetAwaiter().GetResult();
    }

    public void Dispose() => _database.Dispose();

    [Fact]
    public async Task Changing_a_recorded_price_is_rejected()
    {
        await using var db = _database.CreateContext();
        var entry = await db.PriceEntries.FirstAsync();

        entry.PriceCents += 10;

        await Assert.ThrowsAsync<PriceHistoryImmutableException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Deleting_a_price_is_rejected()
    {
        await using var db = _database.CreateContext();
        db.PriceEntries.Remove(await db.PriceEntries.FirstAsync());

        await Assert.ThrowsAsync<PriceHistoryImmutableException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Moderating_price_status_is_allowed()
    {
        long id;
        await using (var db = _database.CreateContext())
        {
            var entry = await db.PriceEntries.FirstAsync(p => p.Status == PriceStatus.Pending);
            id = entry.Id;
            entry.Status = PriceStatus.Approved;
            await db.SaveChangesAsync();
        }

        await using var verify = _database.CreateContext();
        Assert.Equal(PriceStatus.Approved, (await verify.PriceEntries.FindAsync(id))!.Status);
    }

    [Fact]
    public async Task Database_triggers_block_price_changes_that_bypass_ef()
    {
        await using var db = _database.CreateContext();

        var update = await Assert.ThrowsAsync<SqliteException>(() =>
            db.Database.ExecuteSqlRawAsync("""UPDATE "PriceEntries" SET "PriceCents" = 1"""));
        var delete = await Assert.ThrowsAsync<SqliteException>(() =>
            db.Database.ExecuteSqlRawAsync("""DELETE FROM "PriceEntries" """));

        Assert.Contains("immutable", update.Message);
        Assert.Contains("cannot be deleted", delete.Message);
    }

    [Fact]
    public async Task Product_with_same_normalized_name_and_volume_is_rejected()
    {
        await using var db = _database.CreateContext();
        db.Products.Add(NewProduct("  ŠVYTURYS   ekstra ", 500));

        await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Product_with_same_name_but_other_volume_is_allowed()
    {
        await using var db = _database.CreateContext();
        db.Products.Add(NewProduct("Švyturys Ekstra", 1000));

        await db.SaveChangesAsync();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(50_001)]
    public async Task Price_outside_allowed_cents_range_is_rejected(int cents)
    {
        await using var db = _database.CreateContext();
        db.PriceEntries.Add(NewPrice(await db.Products.Select(p => p.Id).FirstAsync(),
            await db.Stores.Select(s => s.Id).FirstAsync(), cents));

        await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
    }

    [Fact]
    public async Task Foreign_keys_are_enforced()
    {
        await using var db = _database.CreateContext();
        db.PriceEntries.Add(NewPrice(productId: 999_999, storeId: 999_999, cents: 150));

        var ex = await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        Assert.Contains("FOREIGN KEY", ex.InnerException!.Message);
    }

    private static Product NewProduct(string name, int volumeMl) => new()
    {
        Name = name.Trim(),
        NormalizedName = TextNormalizer.NormalizeName(name),
        VolumeMl = volumeMl,
        CreatedAt = DateTime.UtcNow,
    };

    private static PriceEntry NewPrice(long productId, long storeId, int cents) => new()
    {
        ProductId = productId,
        StoreId = storeId,
        PriceCents = cents,
        Status = PriceStatus.Pending,
        ObservedAt = DateTime.UtcNow,
        CreatedAt = DateTime.UtcNow,
    };
}
