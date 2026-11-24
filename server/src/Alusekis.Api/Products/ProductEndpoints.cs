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
        return v1;
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
