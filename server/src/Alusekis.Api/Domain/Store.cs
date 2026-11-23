namespace Alusekis.Api.Domain;

public class Store
{
    public long Id { get; set; }

    public long CityId { get; set; }

    public City City { get; set; } = null!;

    public required string Name { get; set; }

    public required string Address { get; set; }

    /// <summary>WGS 84 latitude in degrees (-90..90); null while the location is unknown.</summary>
    public double? Latitude { get; set; }

    /// <summary>WGS 84 longitude in degrees (-180..180); null while the location is unknown.</summary>
    public double? Longitude { get; set; }

    public DateTime CreatedAt { get; set; }

    public List<PriceEntry> PriceEntries { get; set; } = [];
}
