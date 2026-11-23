using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Seeding;

/// <summary>
/// Inserts <see cref="SeedData"/> rows that are missing, matching existing rows by natural key
/// (email, normalized name, name+address, name+volume, product+store+observed time).
/// Idempotent: running it again inserts nothing.
/// </summary>
public sealed class DataSeeder(AppDbContext db)
{
    public async Task<SeedResult> SeedAsync(CancellationToken cancellationToken = default)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        var (user, usersCreated) = await EnsureTestUserAsync(cancellationToken);
        var (cities, citiesCreated) = await EnsureCitiesAsync(cancellationToken);
        var (stores, storesCreated) = await EnsureStoresAsync(cities, cancellationToken);
        var (products, productsCreated) = await EnsureProductsAsync(user, cancellationToken);
        var pricesCreated = await EnsurePricesAsync(user, stores, products, cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return new SeedResult(usersCreated, citiesCreated, storesCreated, productsCreated, pricesCreated);
    }

    private async Task<(User User, int Created)> EnsureTestUserAsync(CancellationToken ct)
    {
        var seed = SeedData.TestUser;
        var normalizedEmail = TextNormalizer.NormalizeEmail(seed.Email);

        var existing = await db.Users.SingleOrDefaultAsync(u => u.NormalizedEmail == normalizedEmail, ct);
        if (existing is not null)
        {
            return (existing, 0);
        }

        var user = new User
        {
            Email = seed.Email,
            NormalizedEmail = normalizedEmail,
            DisplayName = seed.DisplayName,
            Role = seed.Role,
            CreatedAt = SeedData.Anchor,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        return (user, 1);
    }

    private async Task<(Dictionary<string, City> ByName, int Created)> EnsureCitiesAsync(CancellationToken ct)
    {
        var byNormalized = await db.Cities.ToDictionaryAsync(c => c.NormalizedName, ct);
        var created = 0;

        foreach (var name in SeedData.Cities)
        {
            var normalized = TextNormalizer.NormalizeName(name);
            if (byNormalized.ContainsKey(normalized))
            {
                continue;
            }

            var city = new City { Name = name, NormalizedName = normalized };
            db.Cities.Add(city);
            byNormalized[normalized] = city;
            created++;
        }

        await db.SaveChangesAsync(ct);
        return (SeedData.Cities.ToDictionary(n => n, n => byNormalized[TextNormalizer.NormalizeName(n)]), created);
    }

    private async Task<(List<Store> InSeedOrder, int Created)> EnsureStoresAsync(
        Dictionary<string, City> cities, CancellationToken ct)
    {
        var existing = await db.Stores.ToDictionaryAsync(s => (s.CityId, s.Name, s.Address), ct);
        var result = new List<Store>(SeedData.Stores.Count);
        var created = 0;

        foreach (var seed in SeedData.Stores)
        {
            var cityId = cities[seed.City].Id;
            if (!existing.TryGetValue((cityId, seed.Name, seed.Address), out var store))
            {
                store = new Store { CityId = cityId, Name = seed.Name, Address = seed.Address, CreatedAt = SeedData.Anchor };
                db.Stores.Add(store);
                existing[(cityId, seed.Name, seed.Address)] = store;
                created++;
            }

            result.Add(store);
        }

        await db.SaveChangesAsync(ct);
        return (result, created);
    }

    private async Task<(List<Product> InSeedOrder, int Created)> EnsureProductsAsync(User createdBy, CancellationToken ct)
    {
        var existing = await db.Products.ToDictionaryAsync(p => (p.NormalizedName, p.VolumeMl), ct);
        var result = new List<Product>(SeedData.Products.Count);
        var created = 0;

        foreach (var seed in SeedData.Products)
        {
            var key = (TextNormalizer.NormalizeName(seed.Name), seed.VolumeMl);
            if (!existing.TryGetValue(key, out var product))
            {
                product = new Product
                {
                    Name = seed.Name,
                    NormalizedName = key.Item1,
                    VolumeMl = seed.VolumeMl,
                    Brand = seed.Brand,
                    CreatedByUserId = createdBy.Id,
                    CreatedAt = SeedData.Anchor,
                };
                db.Products.Add(product);
                existing[key] = product;
                created++;
            }

            result.Add(product);
        }

        await db.SaveChangesAsync(ct);
        return (result, created);
    }

    private async Task<int> EnsurePricesAsync(
        User submittedBy, List<Store> stores, List<Product> products, CancellationToken ct)
    {
        var existing = (await db.PriceEntries
                .Select(p => new { p.ProductId, p.StoreId, p.ObservedAt })
                .ToListAsync(ct))
            .Select(p => (p.ProductId, p.StoreId, p.ObservedAt))
            .ToHashSet();
        var created = 0;

        foreach (var seed in SeedData.Prices)
        {
            var productId = products[seed.ProductIndex].Id;
            var storeId = stores[seed.StoreIndex].Id;
            if (!existing.Add((productId, storeId, seed.ObservedAt)))
            {
                continue;
            }

            db.PriceEntries.Add(new PriceEntry
            {
                ProductId = productId,
                StoreId = storeId,
                SubmittedByUserId = submittedBy.Id,
                PriceCents = seed.PriceCents,
                Status = seed.Status,
                ObservedAt = seed.ObservedAt,
                CreatedAt = seed.ObservedAt,
            });
            created++;
        }

        await db.SaveChangesAsync(ct);
        return created;
    }
}

public sealed record SeedResult(int Users, int Cities, int Stores, int Products, int Prices)
{
    public int Total => Users + Cities + Stores + Products + Prices;
}
