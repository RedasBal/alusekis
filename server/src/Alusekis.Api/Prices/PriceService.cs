using System.Text.Json;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Prices;

/// <param name="ConfirmLargeChange">The submitter accepts a change of more than 50 %.</param>
public sealed record CreatePriceCommand(
    long UserId,
    long ProductId,
    long StoreId,
    int PriceCents,
    bool ConfirmLargeChange);

public enum PriceCreationStatus
{
    Created,
    InvalidPrice,
    ProductNotFound,
    StoreNotFound,

    /// <summary>More than 50 % away from the previous valid price and not confirmed.</summary>
    LargeChangeNotConfirmed,
}

/// <param name="Entry">The new entry, when <see cref="Status"/> is <see cref="PriceCreationStatus.Created"/>.</param>
/// <param name="PreviousPriceCents">The previous valid price of the pair, if there was one.</param>
public sealed record PriceCreationResult(
    PriceCreationStatus Status,
    PriceEntry? Entry = null,
    int? PreviousPriceCents = null);

/// <summary>
/// Records a new price. Shared by every operation that creates prices (e.g. submitting a price,
/// creating a product with its first price), so they all apply the same rules and audit.
/// </summary>
public interface IPriceService
{
    /// <summary>
    /// Adds a new <see cref="PriceEntry"/> and its <see cref="AuditEntry"/> to the caller's unit of
    /// work. It must be called inside a transaction the caller opened on the same
    /// <see cref="AppDbContext"/>; it flushes changes (to get the new id) but never commits, so
    /// the caller decides whether everything is kept or rolled back together.
    /// A failing check writes nothing.
    /// </summary>
    Task<PriceCreationResult> CreatePriceEntryAsync(CreatePriceCommand command, CancellationToken ct);
}

public sealed class PriceService(AppDbContext db, TimeProvider clock) : IPriceService
{
    public const string AuditAction = "PriceSubmitted";

    public async Task<PriceCreationResult> CreatePriceEntryAsync(CreatePriceCommand command, CancellationToken ct)
    {
        if (db.Database.CurrentTransaction is null)
        {
            throw new InvalidOperationException(
                "CreatePriceEntryAsync must run inside the caller's transaction; it never commits on its own.");
        }

        if (!PriceRules.IsValidPrice(command.PriceCents))
        {
            return new PriceCreationResult(PriceCreationStatus.InvalidPrice);
        }

        if (!await db.Products.AnyAsync(p => p.Id == command.ProductId, ct))
        {
            return new PriceCreationResult(PriceCreationStatus.ProductNotFound);
        }

        if (!await db.Stores.AnyAsync(s => s.Id == command.StoreId, ct))
        {
            return new PriceCreationResult(PriceCreationStatus.StoreNotFound);
        }

        // The previous valid price of this pair: newest approved entry (ObservedAt DESC, Id DESC).
        var previous = await db.PriceEntries.AsNoTracking()
            .Where(p => p.ProductId == command.ProductId
                && p.StoreId == command.StoreId
                && p.Status == PriceStatus.Approved)
            .OrderByDescending(p => p.ObservedAt)
            .ThenByDescending(p => p.Id)
            .Select(p => (int?)p.PriceCents)
            .FirstOrDefaultAsync(ct);

        var isLargeChange = previous is { } old && PriceRules.IsLargeChange(old, command.PriceCents);
        if (isLargeChange && !command.ConfirmLargeChange)
        {
            return new PriceCreationResult(PriceCreationStatus.LargeChangeNotConfirmed, PreviousPriceCents: previous);
        }

        // Always a new row: price history is append-only, earlier entries are never touched.
        var now = clock.GetUtcNow().UtcDateTime;
        var entry = new PriceEntry
        {
            ProductId = command.ProductId,
            StoreId = command.StoreId,
            SubmittedByUserId = command.UserId,
            PriceCents = command.PriceCents,
            Status = PriceStatus.Approved,
            ObservedAt = now,
            CreatedAt = now,
            IsLargeChange = isLargeChange,
        };
        db.PriceEntries.Add(entry);
        await db.SaveChangesAsync(ct); // inside the caller's transaction: not committed yet

        db.AuditEntries.Add(new AuditEntry
        {
            ActorUserId = command.UserId,
            Action = AuditAction,
            EntityType = nameof(PriceEntry),
            EntityId = entry.Id,
            // No secrets: no idempotency key, token or password, only what the price is.
            DetailsJson = JsonSerializer.Serialize(new
            {
                productId = command.ProductId,
                storeId = command.StoreId,
                priceCents = command.PriceCents,
                isLargeChange,
            }),
            CreatedAt = now,
        });
        await db.SaveChangesAsync(ct);

        return new PriceCreationResult(PriceCreationStatus.Created, entry, previous);
    }
}
