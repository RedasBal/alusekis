using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Prices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using HttpJsonOptions = Microsoft.AspNetCore.Http.Json.JsonOptions;

namespace Alusekis.Api.Products;

/// <param name="IdempotencyKey">Chosen by the client (e.g. a UUID) and reused for retries of the same submission.</param>
public sealed record CreateProductRequest(
    string? Name,
    int? VolumeMl,
    long? StoreId,
    int? PriceCents,
    string? IdempotencyKey);

public sealed record NewProductDto(long Id, string Name, int VolumeMl);

public sealed record CreateProductResponse(NewProductDto Product, SubmittedPriceDto Price);

/// <summary>The standard error shape plus the product that already exists, as a suggestion.</summary>
public sealed record ProductExistsDto(string Code, string Message, string RequestId, NewProductDto ExistingProduct);

/// <summary><c>POST /api/v1/products</c>: a signed-in User or Admin adds a missing product with its first price.</summary>
public static class ProductCreation
{
    public const int MinNameLength = 2;
    public const int MaxNameLength = 150;

    internal static async Task<IResult> CreateAsync(
        CreateProductRequest request,
        HttpContext http,
        AppDbContext db,
        IPriceService prices,
        TimeProvider clock,
        IOptions<HttpJsonOptions> jsonOptions,
        CancellationToken ct)
    {
        // ---- input (nothing is written when it is wrong) ----
        var key = request.IdempotencyKey;
        if (string.IsNullOrWhiteSpace(key) || key.Length > PriceEndpoints.MaxIdempotencyKeyLength)
        {
            return Invalid(http, $"idempotencyKey is required (1-{PriceEndpoints.MaxIdempotencyKeyLength} characters).");
        }

        var name = request.Name?.Trim() ?? string.Empty;
        if (name.Length is < MinNameLength or > MaxNameLength)
        {
            return Invalid(http, $"name must be {MinNameLength}-{MaxNameLength} characters long.");
        }

        // The same function the product search uses, so both always agree on what "the same name" is.
        var normalizedName = TextNormalizer.NormalizeName(name);
        if (normalizedName.Length == 0)
        {
            return Invalid(http, "name must contain letters or digits.");
        }

        if (request.VolumeMl is not { } volumeMl
            || volumeMl is < DomainLimits.MinVolumeMl or > DomainLimits.MaxVolumeMl)
        {
            return Invalid(http, $"volumeMl must be {DomainLimits.MinVolumeMl}-{DomainLimits.MaxVolumeMl}.");
        }

        if (request.StoreId is not { } storeId)
        {
            return Invalid(http, "storeId is required.");
        }

        if (request.PriceCents is not { } priceCents || !PriceRules.IsValidPrice(priceCents))
        {
            return PriceInvalid(http);
        }

        var userId = http.User.GetUserId();
        var fingerprint = Fingerprint(normalizedName, volumeMl, storeId, priceCents);

        // ---- a retry of an earlier successful request: answer it again, create nothing ----
        if (await PriceEndpoints.ReplayAsync(http, db, userId, key, fingerprint, ct) is { } replayed)
        {
            return replayed;
        }

        // ---- one transaction: product + first price + audit + stored result, all or nothing ----
        // Leaving without CommitAsync (early return or exception) rolls everything back.
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        try
        {
            if (!await db.Stores.AnyAsync(s => s.Id == storeId, ct))
            {
                return NotFound(http, "Store not found.");
            }

            if (await FindExistingAsync(db, normalizedName, volumeMl, ct) is { } existing)
            {
                return ProductExists(http, jsonOptions, existing);
            }

            var now = clock.GetUtcNow().UtcDateTime;
            var product = new Product
            {
                Name = name,
                NormalizedName = normalizedName,
                VolumeMl = volumeMl,
                CreatedByUserId = userId,
                CreatedAt = now,
            };
            db.Products.Add(product);
            await db.SaveChangesAsync(ct); // inside the transaction: not committed yet

            // The shared price logic; there is no earlier price, so the 50 % rule cannot apply.
            var priceResult = await prices.CreatePriceEntryAsync(
                new CreatePriceCommand(userId, product.Id, storeId, priceCents, ConfirmLargeChange: false), ct);
            switch (priceResult.Status)
            {
                case PriceCreationStatus.Created:
                    break;
                case PriceCreationStatus.InvalidPrice:
                    return PriceInvalid(http); // rolled back, the product is not kept
                case PriceCreationStatus.StoreNotFound:
                    return NotFound(http, "Store not found.");
                default:
                    throw new InvalidOperationException(
                        $"Unexpected price creation result {priceResult.Status} for a brand new product.");
            }

            var entry = priceResult.Entry!;
            db.AuditEntries.Add(new AuditEntry
            {
                ActorUserId = userId,
                Action = "ProductCreated",
                EntityType = nameof(Product),
                EntityId = product.Id,
                // No secrets: no idempotency key, token or password.
                DetailsJson = JsonSerializer.Serialize(new
                {
                    name = product.Name,
                    volumeMl = product.VolumeMl,
                    storeId,
                    priceCents,
                }),
                CreatedAt = now,
            });

            var responseJson = JsonSerializer.Serialize(
                new CreateProductResponse(
                    new NewProductDto(product.Id, product.Name, product.VolumeMl),
                    new SubmittedPriceDto(
                        entry.Id, entry.ProductId, entry.StoreId, entry.PriceCents, entry.ObservedAt, entry.IsLargeChange)),
                jsonOptions.Value.SerializerOptions);

            db.RequestResults.Add(new RequestResult
            {
                UserId = userId,
                IdempotencyKey = key,
                RequestFingerprint = fingerprint,
                StatusCode = StatusCodes.Status201Created,
                ResponseJson = responseJson,
                CreatedAt = now,
            });

            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Results.Text(responseJson, "application/json", Encoding.UTF8, StatusCodes.Status201Created);
        }
        catch (DbUpdateException ex) when (PriceEndpoints.IsUniqueViolation(ex))
        {
            await transaction.RollbackAsync(ct);
            db.ChangeTracker.Clear();

            // Lost a race: another request created the same product (name + volume) first.
            if (ex.InnerException?.Message.Contains("Products.", StringComparison.Ordinal) == true
                && await FindExistingAsync(db, normalizedName, volumeMl, ct) is { } winner)
            {
                return ProductExists(http, jsonOptions, winner);
            }

            // Otherwise a concurrent request with the same idempotency key won: answer like a retry.
            return await PriceEndpoints.ReplayAsync(http, db, userId, key, fingerprint, ct)
                ?? ErrorResponses.Result(
                    http, StatusCodes.Status409Conflict, ErrorCodes.Conflict, "The request conflicted with another one.");
        }
    }

    private static Task<NewProductDto?> FindExistingAsync(
        AppDbContext db, string normalizedName, int volumeMl, CancellationToken ct) =>
        db.Products.AsNoTracking()
            .Where(p => p.NormalizedName == normalizedName && p.VolumeMl == volumeMl)
            .Select(p => new NewProductDto(p.Id, p.Name, p.VolumeMl))
            .FirstOrDefaultAsync(ct);

    private static IResult ProductExists(HttpContext http, IOptions<HttpJsonOptions> jsonOptions, NewProductDto existing) =>
        Results.Json(
            new ProductExistsDto(
                ErrorCodes.ProductExists,
                "A product with this name and volume already exists.",
                http.TraceIdentifier,
                existing),
            jsonOptions.Value.SerializerOptions,
            statusCode: StatusCodes.Status409Conflict);

    /// <summary>What makes two requests "the same": the fields that decide what is recorded.</summary>
    private static string Fingerprint(string normalizedName, int volumeMl, long storeId, int priceCents)
    {
        var canonical = string.Join(
            '|',
            normalizedName,
            volumeMl.ToString(CultureInfo.InvariantCulture),
            storeId.ToString(CultureInfo.InvariantCulture),
            priceCents.ToString(CultureInfo.InvariantCulture));
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }

    private static IResult Invalid(HttpContext http, string message) =>
        ErrorResponses.Result(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.ValidationFailed, message);

    private static IResult PriceInvalid(HttpContext http) =>
        ErrorResponses.Result(
            http,
            StatusCodes.Status422UnprocessableEntity,
            ErrorCodes.PriceInvalid,
            $"priceCents must be {DomainLimits.MinPriceCents}-{DomainLimits.MaxPriceCents}.");

    private static IResult NotFound(HttpContext http, string message) =>
        ErrorResponses.Result(http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, message);
}
