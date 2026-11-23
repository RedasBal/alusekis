namespace Alusekis.Api.Domain;

public class City
{
    public long Id { get; set; }

    public required string Name { get; set; }

    /// <summary>Unique lookup key, see <see cref="TextNormalizer.NormalizeName"/>.</summary>
    public required string NormalizedName { get; set; }

    public List<Store> Stores { get; set; } = [];
}
