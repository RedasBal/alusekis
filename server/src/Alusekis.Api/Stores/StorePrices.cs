using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Stores;

public sealed record StoreSummaryDto(long Id, string Name, string Address);

public sealed record StorePriceDto(
    long PriceEntryId,
    long ProductId,
    string ProductName,
    int VolumeMl,
    int PriceCents,
    DateTime ObservedAt,
    bool IsStale);

public sealed record StorePricesResponse(
    StoreSummaryDto Store,
    IReadOnlyList<StorePriceDto> Items,
    int Total,
    int Page,
    int PageSize);

/// <summary>The latest valid price of every product in one store.</summary>
public static class StorePrices
{
    public const int DefaultPageSize = 20;
    public const int MaxPageSize = 100;

    /// <summary>Keeps (page - 1) * pageSize far below int.MaxValue.</summary>
    public const int MaxPage = 100_000;

    /// <summary>A price observed longer ago than this (by server time) is flagged stale (FR-17).</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromDays(7);

    /// <summary>
    /// Per product, the newest <see cref="PriceStatus.Approved"/> entry in the store:
    /// the one with no newer sibling (ObservedAt DESC, Id DESC). One SQL statement, no
    /// per-product round trips; the correlated NOT EXISTS is served by
    /// IX_PriceEntries_Product_Store_Status_ObservedAt_Id and the outer filter by
    /// IX_PriceEntries_StoreId.
    /// </summary>
    public static IQueryable<PriceEntry> LatestApproved(AppDbContext db, long storeId) =>
        db.PriceEntries.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Status == PriceStatus.Approved)
            .Where(p => !db.PriceEntries.Any(n =>
                n.StoreId == p.StoreId
                && n.ProductId == p.ProductId
                && n.Status == PriceStatus.Approved
                && (n.ObservedAt > p.ObservedAt || (n.ObservedAt == p.ObservedAt && n.Id > p.Id))));

    /// <summary>Returns null when the store does not exist.</summary>
    public static async Task<StorePricesResponse?> QueryAsync(
        AppDbContext db, DateTime utcNow, long storeId, int page, int pageSize, CancellationToken ct)
    {
        var store = await db.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => new StoreSummaryDto(s.Id, s.Name, s.Address))
            .FirstOrDefaultAsync(ct);
        if (store is null)
        {
            return null;
        }

        var latest = LatestApproved(db, storeId);
        var total = await latest.CountAsync(ct);

        var rows = await latest
            .OrderBy(p => p.Product.NormalizedName)
            .ThenBy(p => p.Product.VolumeMl)
            .ThenBy(p => p.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(p => new
            {
                p.Id,
                p.ProductId,
                ProductName = p.Product.Name,
                p.Product.VolumeMl,
                p.PriceCents,
                p.ObservedAt,
            })
            .ToListAsync(ct);

        var items = rows
            .Select(r => new StorePriceDto(
                r.Id,
                r.ProductId,
                r.ProductName,
                r.VolumeMl,
                r.PriceCents,
                r.ObservedAt,
                IsStale: utcNow - r.ObservedAt > StaleAfter))
            .ToList();

        return new StorePricesResponse(store, items, total, page, pageSize);
    }
}
