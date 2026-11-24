using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Stores;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Products;

public sealed record ProductSummaryDto(long Id, string Name, string? Brand, int VolumeMl);

public sealed record StorePriceComparisonDto(
    long PriceEntryId,
    long StoreId,
    string StoreName,
    string StoreAddress,
    int PriceCents,
    DateTime ObservedAt,
    bool IsStale);

/// <param name="StoreCount">How many stores have a price for the product.</param>
/// <param name="SingleStore">True when only one store has data, so there is nothing to compare.</param>
public sealed record ProductPricesResponse(
    ProductSummaryDto Product,
    IReadOnlyList<StorePriceComparisonDto> Items,
    int StoreCount,
    bool SingleStore);

/// <summary>The newest valid price of one product in every store, for comparison.</summary>
public static class ProductPrices
{
    /// <summary>
    /// Per store, the newest <see cref="PriceStatus.Approved"/> price of the product: the entry with
    /// no newer sibling for the same (product, store) pair, by ObservedAt DESC, Id DESC.
    /// A product is one row (name + volume), so another volume of the same name is never mixed in.
    /// </summary>
    public static IQueryable<PriceEntry> LatestApprovedPerStore(AppDbContext db, long productId) =>
        db.PriceEntries.AsNoTracking()
            .Where(p => p.ProductId == productId && p.Status == PriceStatus.Approved)
            .Where(p => !db.PriceEntries.Any(n =>
                n.ProductId == p.ProductId
                && n.StoreId == p.StoreId
                && n.Status == PriceStatus.Approved
                && (n.ObservedAt > p.ObservedAt || (n.ObservedAt == p.ObservedAt && n.Id > p.Id))));

    /// <summary>
    /// Returns null when the product does not exist. Cheapest first when <paramref name="descending"/>
    /// is false; equal prices always by store id (ascending) so the order is stable.
    /// Two statements: the product, then its prices.
    /// </summary>
    public static async Task<ProductPricesResponse?> QueryAsync(
        AppDbContext db, DateTime utcNow, long productId, bool descending, CancellationToken ct)
    {
        var product = await db.Products.AsNoTracking()
            .Where(p => p.Id == productId)
            .Select(p => new ProductSummaryDto(p.Id, p.Name, p.Brand, p.VolumeMl))
            .FirstOrDefaultAsync(ct);
        if (product is null)
        {
            return null;
        }

        var latest = LatestApprovedPerStore(db, productId);
        var ordered = descending
            ? latest.OrderByDescending(p => p.PriceCents).ThenBy(p => p.StoreId)
            : latest.OrderBy(p => p.PriceCents).ThenBy(p => p.StoreId);

        var rows = await ordered
            .Select(p => new
            {
                p.Id,
                p.StoreId,
                StoreName = p.Store.Name,
                StoreAddress = p.Store.Address,
                p.PriceCents,
                p.ObservedAt,
            })
            .ToListAsync(ct);

        var items = rows
            .Select(r => new StorePriceComparisonDto(
                r.Id,
                r.StoreId,
                r.StoreName,
                r.StoreAddress,
                r.PriceCents,
                r.ObservedAt,
                IsStale: utcNow - r.ObservedAt > StorePrices.StaleAfter))
            .ToList();

        return new ProductPricesResponse(product, items, items.Count, SingleStore: items.Count == 1);
    }
}
