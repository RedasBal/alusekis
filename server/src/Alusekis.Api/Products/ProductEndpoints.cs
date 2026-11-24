using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;

namespace Alusekis.Api.Products;

/// <summary>Public (guest) product endpoints under <c>/api/v1/products</c>.</summary>
public static class ProductEndpoints
{
    public static RouteGroupBuilder MapProducts(this RouteGroupBuilder v1)
    {
        v1.MapGet("/products/search", Search);
        v1.MapGet("/products/{id:long}/prices", GetPrices);
        v1.MapGet("/products/{productId:long}/stores/{storeId:long}/history", GetHistory);
        return v1;
    }

    /// <summary>
    /// The recorded prices of one product in one store over the last <c>days</c> days (7, 30 or 90;
    /// 30 when missing). Taken as text so that every wrong value gives the same 422.
    /// </summary>
    private static async Task<IResult> GetHistory(
        HttpContext http,
        AppDbContext db,
        TimeProvider clock,
        long productId,
        long storeId,
        string? days,
        CancellationToken ct)
    {
        if (!PriceHistory.TryParseDays(days, out var window))
        {
            return ErrorResponses.Result(
                http,
                StatusCodes.Status422UnprocessableEntity,
                ErrorCodes.ValidationFailed,
                "days must be 7, 30 or 90.");
        }

        var outcome = await PriceHistory.QueryAsync(
            db, clock.GetUtcNow().UtcDateTime, productId, storeId, window, ct);

        return outcome.Failure switch
        {
            HistoryLookupFailure.ProductNotFound => ErrorResponses.Result(
                http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Product not found."),
            HistoryLookupFailure.StoreNotFound => ErrorResponses.Result(
                http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Store not found."),
            _ => Results.Ok(outcome.Response),
        };
    }

    /// <summary>
    /// The product's newest valid price in every store. <c>sort</c> is <c>asc</c> (default, cheapest
    /// first) or <c>desc</c>; anything else is rejected.
    /// </summary>
    private static async Task<IResult> GetPrices(
        HttpContext http,
        AppDbContext db,
        TimeProvider clock,
        long id,
        string? sort,
        CancellationToken ct)
    {
        bool descending;
        if (sort is null || sort.Equals("asc", StringComparison.OrdinalIgnoreCase))
        {
            descending = false;
        }
        else if (sort.Equals("desc", StringComparison.OrdinalIgnoreCase))
        {
            descending = true;
        }
        else
        {
            return ErrorResponses.Result(
                http,
                StatusCodes.Status422UnprocessableEntity,
                ErrorCodes.ValidationFailed,
                "sort must be asc or desc.");
        }

        var result = await ProductPrices.QueryAsync(db, clock.GetUtcNow().UtcDateTime, id, descending, ct);
        return result is null
            ? ErrorResponses.Result(http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Product not found.")
            : Results.Ok(result);
    }

    /// <summary>
    /// <c>q</c> is trimmed and must be 2-100 characters. No match is an empty list, not an error.
    /// </summary>
    private static async Task<IResult> Search(
        HttpContext http,
        AppDbContext db,
        TimeProvider clock,
        string? q,
        CancellationToken ct)
    {
        var text = q?.Trim() ?? string.Empty;
        if (text.Length is < ProductSearch.MinQueryLength or > ProductSearch.MaxQueryLength)
        {
            return ErrorResponses.Result(
                http,
                StatusCodes.Status422UnprocessableEntity,
                ErrorCodes.ValidationFailed,
                $"q must be {ProductSearch.MinQueryLength}-{ProductSearch.MaxQueryLength} characters long.");
        }

        var result = await ProductSearch.SearchAsync(
            db, clock.GetUtcNow().UtcDateTime, TextNormalizer.NormalizeName(text), ct);
        return Results.Ok(result);
    }
}
