using Alusekis.Api.Domain;

namespace Alusekis.Api.Seeding;

/// <summary>
/// Fixed development/demo data set. Everything (including dates) is deterministic so the
/// seeder can recognise rows it already inserted and re-runs never create duplicates.
/// </summary>
public static class SeedData
{
    /// <summary>All seeded timestamps are derived from this instant, never from the current clock.</summary>
    public static readonly DateTime Anchor = new(2026, 11, 1, 12, 0, 0, DateTimeKind.Utc);

    public static readonly SeedUser TestUser = new("test@alusekis.local", "Testinis vartotojas", Role.User);

    public static readonly IReadOnlyList<string> Cities = ["Vilnius", "Kaunas", "Klaipėda"];

    public static readonly IReadOnlyList<SeedStore> Stores =
    [
        new("Vilnius", "Maxima XX", "Ukmergės g. 282"),
        new("Vilnius", "Rimi Hyper", "Ozo g. 25"),
        new("Vilnius", "Iki", "Žirmūnų g. 64"),
        new("Vilnius", "Lidl", "Kalvarijų g. 202"),
        new("Vilnius", "Norfa", "Šeškinės g. 12"),
        new("Kaunas", "Maxima XXX", "Savanorių pr. 255"),
        new("Kaunas", "Rimi", "Jonavos g. 3"),
        new("Kaunas", "Iki", "Pramonės pr. 16"),
        new("Kaunas", "Lidl", "Taikos pr. 141"),
        new("Klaipėda", "Maxima XX", "Taikos pr. 61"),
        new("Klaipėda", "Rimi", "Liepojos g. 10"),
        new("Klaipėda", "Norfa", "Šilutės pl. 35"),
    ];

    public static readonly IReadOnlyList<SeedProduct> Products =
    [
        new("Švyturys Ekstra", "Švyturys", 500, 149),
        new("Švyturys Ekstra", "Švyturys", 330, 109),
        new("Švyturys Baltijos", "Švyturys", 500, 139),
        new("Švyturys Gintarinis", "Švyturys", 500, 129),
        new("Švyturys Ekstra Draught", "Švyturys", 568, 179),
        new("Švyturys Ekstra Nealkoholinis", "Švyturys", 500, 139),
        new("Utenos Originalus", "Utenos", 500, 119),
        new("Utenos Originalus", "Utenos", 1000, 209),
        new("Utenos Porteris", "Utenos", 500, 159),
        new("Utenos Dark", "Utenos", 500, 139),
        new("Kalnapilis Originalus", "Kalnapilis", 500, 125),
        new("Kalnapilis Grand", "Kalnapilis", 500, 145),
        new("Kalnapilis 7.30", "Kalnapilis", 568, 169),
        new("Kalnapilis Selected", "Kalnapilis", 330, 129),
        new("Volfas Engelman Kaunietiškas", "Volfas Engelman", 500, 165),
        new("Volfas Engelman Grünberger", "Volfas Engelman", 500, 175),
        new("Volfas Engelman IPA", "Volfas Engelman", 500, 199),
        new("Tauras Tradicinis", "Tauras", 500, 115),
        new("Tauras Tradicinis", "Tauras", 1500, 279),
        new("Rinkuškiai Ekstra", "Rinkuškiai", 500, 155),
        new("Rinkuškiai Klasikinis", "Rinkuškiai", 1000, 259),
        new("Biržų Duona", "Biržų alus", 500, 179),
        new("Dundulis Bravorinis", "Dundulis", 500, 219),
        new("Dundulis Kvietinis", "Dundulis", 500, 229),
        new("Sakiškių Šviesusis", "Sakiškių alus", 500, 189),
        new("Horn Kaimiškas Šviesusis", "Horn", 1000, 239),
        new("Heineken", "Heineken", 500, 159),
        new("Heineken", "Heineken", 330, 119),
        new("Carlsberg", "Carlsberg", 500, 149),
        new("Guinness Draught", "Guinness", 440, 249),
    ];

    /// <summary>
    /// 60 prices with distinct observation dates over ~6 weeks:
    /// products 0–4 in three stores, 5–9 in two stores with two observations (history) in the first,
    /// 10–19 in two stores, 20–29 in one store.
    /// </summary>
    public static IReadOnlyList<SeedPrice> Prices { get; } = BuildPrices();

    private static List<SeedPrice> BuildPrices()
    {
        var prices = new List<SeedPrice>();

        for (var p = 0; p < Products.Count; p++)
        {
            var first = (p * 5) % Stores.Count;
            var second = (p * 5 + 7) % Stores.Count;
            var third = (p * 5 + 2) % Stores.Count;

            int[] storeIndexes = p switch
            {
                < 5 => [first, second, third],
                < 10 => [first, first, second],
                < 20 => [first, second],
                _ => [first],
            };

            foreach (var storeIndex in storeIndexes)
            {
                var n = prices.Count;
                var cents = Math.Max(DomainLimits.MinPriceCents, Products[p].BaseCents + (n * 37 % 41) - 20);
                var status = n % 12 == 11 ? PriceStatus.Pending : PriceStatus.Approved;
                var observedAt = Anchor.AddHours(-(n * 17 + 3));
                prices.Add(new SeedPrice(p, storeIndex, cents, status, observedAt));
            }
        }

        return prices;
    }
}

public sealed record SeedUser(string Email, string DisplayName, Role Role);

public sealed record SeedStore(string City, string Name, string Address);

public sealed record SeedProduct(string Name, string Brand, int VolumeMl, int BaseCents);

public sealed record SeedPrice(int ProductIndex, int StoreIndex, int PriceCents, PriceStatus Status, DateTime ObservedAt);
