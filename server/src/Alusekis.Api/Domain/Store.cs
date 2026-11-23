namespace Alusekis.Api.Domain;

public class Store
{
    public long Id { get; set; }

    public long CityId { get; set; }

    public City City { get; set; } = null!;

    public required string Name { get; set; }

    public required string Address { get; set; }

    public DateTime CreatedAt { get; set; }

    public List<PriceEntry> PriceEntries { get; set; } = [];
}
