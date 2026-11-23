namespace Alusekis.Api.Domain;

public class Product
{
    public long Id { get; set; }

    public required string Name { get; set; }

    /// <summary>
    /// Lookup key, see <see cref="TextNormalizer.NormalizeName"/>.
    /// (NormalizedName, VolumeMl) is unique.
    /// </summary>
    public required string NormalizedName { get; set; }

    /// <summary>Volume in whole millilitres, <see cref="DomainLimits.MinVolumeMl"/>..<see cref="DomainLimits.MaxVolumeMl"/>.</summary>
    public int VolumeMl { get; set; }

    public string? Brand { get; set; }

    public long? CreatedByUserId { get; set; }

    public User? CreatedBy { get; set; }

    public DateTime CreatedAt { get; set; }

    public List<PriceEntry> PriceEntries { get; set; } = [];
}
