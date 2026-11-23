namespace Alusekis.Api.Domain;

/// <summary>
/// One observed price of a product in a store. Price history is append-only:
/// a new price is always a new row. Only <see cref="Status"/> may change after insert
/// (moderation); rows are never deleted. Enforced in <c>AppDbContext</c> and by DB triggers.
/// </summary>
public class PriceEntry
{
    public long Id { get; set; }

    public long ProductId { get; set; }

    public Product Product { get; set; } = null!;

    public long StoreId { get; set; }

    public Store Store { get; set; } = null!;

    public long? SubmittedByUserId { get; set; }

    public User? SubmittedBy { get; set; }

    /// <summary>Price in whole euro cents, <see cref="DomainLimits.MinPriceCents"/>..<see cref="DomainLimits.MaxPriceCents"/>.</summary>
    public int PriceCents { get; set; }

    public PriceStatus Status { get; set; } = PriceStatus.Pending;

    /// <summary>When the price was seen/checked in the store (UTC).</summary>
    public DateTime ObservedAt { get; set; }

    /// <summary>When the row was recorded on the server (UTC).</summary>
    public DateTime CreatedAt { get; set; }
}
