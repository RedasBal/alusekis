using System.Text.Json.Serialization;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Products;

public sealed record LowestPriceDto(int PriceCents, long StoreId, string StoreName, DateTime ObservedAt, bool IsStale);

public sealed record ProductSearchItemDto(
    long Id,
    string Name,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Brand,
    int VolumeMl,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LowestPriceDto? LowestPrice);

public sealed record ProductSearchResponse(IReadOnlyList<ProductSearchItemDto> Items);

/// <summary>Finds products by part of their name.</summary>
public static class ProductSearch
{
    public const int MinQueryLength = 2;
    public const int MaxQueryLength = 100;
    public const int MaxResults = 50;

    /// <summary>A price observed longer ago than this (by server time) is flagged stale (FR-17).</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromDays(7);

    /// <summary>
    /// Matches <paramref name="normalizedQuery"/> (already passed through
    /// <see cref="TextNormalizer.NormalizeName"/>) against <see cref="Product.NormalizedName"/>,
    /// which was produced by the same function: lower case and without diacritics, so
    /// "ŽALGIRIS", "žalgiris" and "Zalgiris" all find "Žalgiris". The text only ever travels as
    /// a query parameter and is compared literally (no LIKE wildcards), so %, _ and ' are
    /// ordinary characters.
    /// At most two statements: the products, then (if any matched) their prices.
    /// </summary>
    public static async Task<ProductSearchResponse> SearchAsync(
        AppDbContext db, DateTime utcNow, string normalizedQuery, CancellationToken ct)
    {
        if (normalizedQuery.Length == 0)
        {
            return new ProductSearchResponse([]); // would otherwise match every product
        }

        var products = await db.Products.AsNoTracking()
            .Where(p => p.NormalizedName.Contains(normalizedQuery))
            .OrderBy(p => p.NormalizedName.StartsWith(normalizedQuery) ? 0 : 1)
            .ThenBy(p => p.NormalizedName)
            .ThenBy(p => p.VolumeMl)
            .ThenBy(p => p.Id)
            .Take(MaxResults)
            .Select(p => new { p.Id, p.Name, p.Brand, p.VolumeMl })
            .ToListAsync(ct);

        if (products.Count == 0)
        {
            return new ProductSearchResponse([]);
        }

        var lowest = await LowestPricesAsync(db, products.Select(p => p.Id).ToList(), ct);

        var items = products
            .Select(p => new ProductSearchItemDto(
                p.Id,
                p.Name,
                p.Brand,
                p.VolumeMl,
                lowest.TryGetValue(p.Id, out var price)
                    ? new LowestPriceDto(
                        price.PriceCents,
                        price.StoreId,
                        price.StoreName,
                        price.ObservedAt,
                        IsStale: utcNow - price.ObservedAt > StaleAfter)
                    : null))
            .ToList();

        return new ProductSearchResponse(items);
    }

    /// <summary>
    /// The cheapest of each product's newest approved prices (one per store). A superseded
    /// older price, a rejected entry or a pending one never counts.
    /// </summary>
    private static async Task<Dictionary<long, PriceRow>> LowestPricesAsync(
        AppDbContext db, List<long> productIds, CancellationToken ct)
    {
        var rows = await db.PriceEntries.AsNoTracking()
            .Where(p => productIds.Contains(p.ProductId) && p.Status == PriceStatus.Approved)
            .Where(p => !db.PriceEntries.Any(n =>
                n.ProductId == p.ProductId
                && n.StoreId == p.StoreId
                && n.Status == PriceStatus.Approved
                && (n.ObservedAt > p.ObservedAt || (n.ObservedAt == p.ObservedAt && n.Id > p.Id))))
            .Select(p => new PriceRow(p.ProductId, p.PriceCents, p.StoreId, p.Store.Name, p.ObservedAt))
            .ToListAsync(ct);

        return rows
            .GroupBy(r => r.ProductId)
            .ToDictionary(
                g => g.Key,
                g => g.OrderBy(r => r.PriceCents)
                    .ThenByDescending(r => r.ObservedAt)
                    .ThenBy(r => r.StoreName, StringComparer.Ordinal)
                    .First());
    }

    private sealed record PriceRow(long ProductId, int PriceCents, long StoreId, string StoreName, DateTime ObservedAt);
}
