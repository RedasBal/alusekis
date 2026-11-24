using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using HttpJsonOptions = Microsoft.AspNetCore.Http.Json.JsonOptions;

namespace Alusekis.Api.Prices;

/// <param name="IdempotencyKey">Chosen by the client (e.g. a UUID) and reused for retries of the same submission.</param>
/// <param name="ConfirmLargeChange">Needed when the price differs more than 50 % from the previous one.</param>
public sealed record SubmitPriceRequest(
    long? ProductId,
    long? StoreId,
    int? PriceCents,
    string? IdempotencyKey,
    bool? ConfirmLargeChange);

public sealed record SubmittedPriceDto(
    long Id,
    long ProductId,
    long StoreId,
    int PriceCents,
    DateTime ObservedAt,
    bool IsLargeChange);

/// <summary>The standard error shape plus the previous price, so the client can ask for confirmation.</summary>
public sealed record LargePriceChangeDto(string Code, string Message, string RequestId, int PreviousPriceCents);

/// <summary><c>POST /api/v1/prices</c>: a signed-in User or Admin records a checked price.</summary>
public static class PriceEndpoints
{
    public const int MaxIdempotencyKeyLength = 100;
    public const string ReplayHeader = "Idempotency-Replayed";

    public static IServiceCollection AddAlusekisPrices(this IServiceCollection services)
    {
        services.AddScoped<IPriceService, PriceService>();
        return services;
    }

    public static RouteGroupBuilder MapPrices(this RouteGroupBuilder v1)
    {
        // Guests: 401 when not signed in, 403 for the Guest role (checked only here, on the server).
        v1.MapPost("/prices", Submit).RequireAuthorization(Policies.User);
        return v1;
    }

    private static async Task<IResult> Submit(
        SubmitPriceRequest request,
        HttpContext http,
        AppDbContext db,
        IPriceService prices,
        TimeProvider clock,
        IOptions<HttpJsonOptions> jsonOptions,
        CancellationToken ct)
    {
        // ---- input (nothing is written when it is wrong) ----
        var key = request.IdempotencyKey;
        if (string.IsNullOrWhiteSpace(key) || key.Length > MaxIdempotencyKeyLength)
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.ValidationFailed,
                $"idempotencyKey is required (1-{MaxIdempotencyKeyLength} characters).");
        }

        if (request.ProductId is not { } productId || request.StoreId is not { } storeId)
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.ValidationFailed,
                "productId and storeId are required.");
        }

        if (request.PriceCents is not { } priceCents || !PriceRules.IsValidPrice(priceCents))
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.PriceInvalid,
                $"priceCents must be {DomainLimits.MinPriceCents}-{DomainLimits.MaxPriceCents}.");
        }

        var confirm = request.ConfirmLargeChange ?? false;
        var userId = http.User.GetUserId();
        var fingerprint = Fingerprint(productId, storeId, priceCents, confirm);

        // ---- a retry of an earlier successful request: answer it again, create nothing ----
        if (await ReplayAsync(http, db, userId, key, fingerprint, ct) is { } replayed)
        {
            return replayed;
        }

        // ---- one transaction: price entry + audit + stored result, all or nothing ----
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        var result = await prices.CreatePriceEntryAsync(
            new CreatePriceCommand(userId, productId, storeId, priceCents, confirm), ct);

        switch (result.Status)
        {
            case PriceCreationStatus.InvalidPrice:
                return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.PriceInvalid,
                    $"priceCents must be {DomainLimits.MinPriceCents}-{DomainLimits.MaxPriceCents}.");
            case PriceCreationStatus.ProductNotFound:
                return Error(http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Product not found.");
            case PriceCreationStatus.StoreNotFound:
                return Error(http, StatusCodes.Status404NotFound, ErrorCodes.NotFound, "Store not found.");
            case PriceCreationStatus.LargeChangeNotConfirmed:
                // Not stored: the client may send the same key again with confirmLargeChange=true.
                return Results.Json(
                    new LargePriceChangeDto(
                        ErrorCodes.LargePriceChange,
                        "The price differs by more than 50% from the previous one; confirm to save it.",
                        http.TraceIdentifier,
                        result.PreviousPriceCents!.Value),
                    jsonOptions.Value.SerializerOptions,
                    statusCode: StatusCodes.Status409Conflict);
        }

        var entry = result.Entry!;
        var responseJson = JsonSerializer.Serialize(
            new SubmittedPriceDto(entry.Id, entry.ProductId, entry.StoreId, entry.PriceCents, entry.ObservedAt, entry.IsLargeChange),
            jsonOptions.Value.SerializerOptions);

        db.RequestResults.Add(new RequestResult
        {
            UserId = userId,
            IdempotencyKey = key,
            RequestFingerprint = fingerprint,
            StatusCode = StatusCodes.Status201Created,
            ResponseJson = responseJson,
            CreatedAt = clock.GetUtcNow().UtcDateTime,
        });

        try
        {
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
        }
        catch (DbUpdateException ex) when (IsUniqueViolation(ex))
        {
            // A concurrent request with the same key won: undo ours and answer like a retry.
            await transaction.RollbackAsync(ct);
            db.ChangeTracker.Clear();
            return await ReplayAsync(http, db, userId, key, fingerprint, ct)
                ?? Error(http, StatusCodes.Status409Conflict, ErrorCodes.Conflict, "The request conflicted with another one.");
        }

        return Results.Text(responseJson, "application/json", Encoding.UTF8, StatusCodes.Status201Created);
    }

    /// <summary>
    /// The stored answer when this user already used <paramref name="key"/>: replayed for the same
    /// content, rejected for different content. Null when the key is new.
    /// </summary>
    internal static async Task<IResult?> ReplayAsync(
        HttpContext http, AppDbContext db, long userId, string key, string fingerprint, CancellationToken ct)
    {
        var stored = await db.RequestResults.AsNoTracking()
            .FirstOrDefaultAsync(r => r.UserId == userId && r.IdempotencyKey == key, ct);
        if (stored is null)
        {
            return null;
        }

        if (stored.RequestFingerprint != fingerprint)
        {
            return Error(http, StatusCodes.Status409Conflict, ErrorCodes.IdempotencyKeyReused,
                "This idempotency key was already used for a different request.");
        }

        http.Response.Headers[ReplayHeader] = "true";
        return Results.Text(stored.ResponseJson, "application/json", Encoding.UTF8, stored.StatusCode);
    }

    /// <summary>What makes two requests "the same": the fields that decide what is recorded.</summary>
    private static string Fingerprint(long productId, long storeId, int priceCents, bool confirm)
    {
        var canonical = string.Join(
            '|',
            productId.ToString(CultureInfo.InvariantCulture),
            storeId.ToString(CultureInfo.InvariantCulture),
            priceCents.ToString(CultureInfo.InvariantCulture),
            confirm ? "1" : "0");
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }

    private static IResult Error(HttpContext http, int status, string code, string message) =>
        ErrorResponses.Result(http, status, code, message);

    internal static bool IsUniqueViolation(DbUpdateException ex) =>
        ex.InnerException is SqliteException { SqliteErrorCode: 19 } sqlite
        && sqlite.Message.Contains("UNIQUE", StringComparison.OrdinalIgnoreCase);
}
