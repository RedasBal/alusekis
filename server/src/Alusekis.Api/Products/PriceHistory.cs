using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Products;

public sealed record HistoryStoreDto(long Id, string Name, string Address);

/// <summary>One recorded price: one entry, one point. Nothing is averaged, filled in or merged.</summary>
public sealed record HistoryPointDto(long PriceEntryId, int PriceCents, DateTime ObservedAt);

/// <param name="Days">The window that was asked for (7, 30 or 90).</param>
/// <param name="From">Start of the window (server time, UTC); entries observed exactly then are included.</param>
/// <param name="To">End of the window: the server's "now" (UTC).</param>
/// <param name="Items">Oldest first.</param>
public sealed record PriceHistoryResponse(
    ProductSummaryDto Product,
    HistoryStoreDto Store,
    int Days,
    DateTime From,
    DateTime To,
    IReadOnlyList<HistoryPointDto> Items);

/// <summary>Why a history could not be produced.</summary>
public enum HistoryLookupFailure
{
    ProductNotFound,
    StoreNotFound,
}

public sealed record PriceHistoryOutcome(PriceHistoryResponse? Response, HistoryLookupFailure? Failure);

/// <summary>The recorded prices of one product in one store over the last 7, 30 or 90 days.</summary>
public static class PriceHistory
{
    public const int DefaultDays = 30;

    private static readonly int[] AllowedDays = [7, 30, 90];

    /// <summary>
    /// A missing value means <see cref="DefaultDays"/>. Otherwise only the exact texts
    /// "7", "30" and "90" are accepted ("07", "7.0", "", "abc", "365" are not).
    /// </summary>
    public static bool TryParseDays(string? raw, out int days)
    {
        if (raw is null)
        {
            days = DefaultDays;
            return true;
        }

        foreach (var allowed in AllowedDays)
        {
            if (raw == allowed.ToString(System.Globalization.CultureInfo.InvariantCulture))
            {
                days = allowed;
                return true;
            }
        }

        days = 0;
        return false;
    }

    /// <summary>
    /// The valid (<see cref="PriceStatus.Approved"/>) entries of the pair observed since
    /// <paramref name="from"/>, oldest first (ObservedAt, then Id). The filter is three equalities and
    /// a range on the columns of IX_PriceEntries_Product_Store_Status_ObservedAt_Id, which also
    /// delivers the rows already in that order.
    /// </summary>
    public static IQueryable<PriceEntry> EntriesSince(AppDbContext db, long productId, long storeId, DateTime from) =>
        db.PriceEntries.AsNoTracking()
            .Where(p => p.ProductId == productId
                && p.StoreId == storeId
                && p.Status == PriceStatus.Approved
                && p.ObservedAt >= from)
            .OrderBy(p => p.ObservedAt)
            .ThenBy(p => p.Id);

    /// <summary>Three statements: the product, the store, the entries. Nothing per entry.</summary>
    public static async Task<PriceHistoryOutcome> QueryAsync(
        AppDbContext db, DateTime utcNow, long productId, long storeId, int days, CancellationToken ct)
    {
        var product = await db.Products.AsNoTracking()
            .Where(p => p.Id == productId)
            .Select(p => new ProductSummaryDto(p.Id, p.Name, p.Brand, p.VolumeMl))
            .FirstOrDefaultAsync(ct);
        if (product is null)
        {
            return new PriceHistoryOutcome(null, HistoryLookupFailure.ProductNotFound);
        }

        var store = await db.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => new HistoryStoreDto(s.Id, s.Name, s.Address))
            .FirstOrDefaultAsync(ct);
        if (store is null)
        {
            return new PriceHistoryOutcome(null, HistoryLookupFailure.StoreNotFound);
        }

        var from = utcNow - TimeSpan.FromDays(days);
        var items = await EntriesSince(db, productId, storeId, from)
            .Select(p => new HistoryPointDto(p.Id, p.PriceCents, p.ObservedAt))
            .ToListAsync(ct);

        return new PriceHistoryOutcome(new PriceHistoryResponse(product, store, days, from, utcNow, items), null);
    }
}
