using Alusekis.Api.Data;
using Alusekis.Api.Seeding;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class SeedIdempotencyTests : IDisposable
{
    private readonly TestDatabase _database = new();

    public void Dispose() => _database.Dispose();

    [Fact]
    public async Task Seeding_twice_produces_the_same_row_counts()
    {
        var firstRun = await SeedAsync();
        var afterFirst = await CountRowsAsync();

        var secondRun = await SeedAsync();
        var afterSecond = await CountRowsAsync();

        Assert.Equal(new RowCounts(Users: 1, Cities: 3, Stores: 12, Products: 30, Prices: 60), afterFirst);
        Assert.Equal(afterFirst, afterSecond);
        Assert.Equal(firstRun.Total, afterFirst.Total);
        Assert.Equal(0, secondRun.Total);
    }

    [Fact]
    public async Task Seed_data_covers_multi_store_products_and_distinct_dates()
    {
        await SeedAsync();
        await using var db = _database.CreateContext();

        var storesPerProduct = await db.PriceEntries
            .GroupBy(p => p.ProductId)
            .Select(g => g.Select(p => p.StoreId).Distinct().Count())
            .ToListAsync();
        var observedDates = await db.PriceEntries.Select(p => p.ObservedAt).ToListAsync();

        Assert.Contains(storesPerProduct, count => count >= 2);
        Assert.Equal(observedDates.Count, observedDates.Distinct().Count());
        Assert.All(observedDates, d => Assert.Equal(DateTimeKind.Utc, d.Kind));
    }

    private async Task<SeedResult> SeedAsync()
    {
        await using var db = _database.CreateContext();
        return await new DataSeeder(db).SeedAsync();
    }

    private async Task<RowCounts> CountRowsAsync()
    {
        await using var db = _database.CreateContext();
        return new RowCounts(
            await db.Users.CountAsync(),
            await db.Cities.CountAsync(),
            await db.Stores.CountAsync(),
            await db.Products.CountAsync(),
            await db.PriceEntries.CountAsync());
    }

    private sealed record RowCounts(int Users, int Cities, int Stores, int Products, int Prices)
    {
        public int Total => Users + Cities + Stores + Products + Prices;
    }
}
