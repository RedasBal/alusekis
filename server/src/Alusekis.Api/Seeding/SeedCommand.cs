using Alusekis.Api.Configuration;
using Alusekis.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Seeding;

/// <summary>
/// CLI mode: <c>dotnet run --project src/Alusekis.Api -- seed</c>.
/// Applies migrations, inserts missing seed data, prints a summary and exits without starting the web server.
/// </summary>
public static class SeedCommand
{
    public const string Name = "seed";

    public static bool IsRequested(string[] args) =>
        args.Length > 0 && string.Equals(args[0], Name, StringComparison.OrdinalIgnoreCase);

    public static async Task<int> RunAsync(IServiceProvider services, CancellationToken cancellationToken = default)
    {
        await services.PrepareDatabaseAsync(forceMigrate: true);

        await using var scope = services.CreateAsyncScope();
        var seeder = scope.ServiceProvider.GetRequiredService<DataSeeder>();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var created = await seeder.SeedAsync(cancellationToken);

        Console.WriteLine(created.Total == 0
            ? "Seed: nothing to insert, database already contains the seed data."
            : $"Seed: inserted {created.Users} user(s), {created.Cities} cities, {created.Stores} stores, " +
              $"{created.Products} products, {created.Prices} prices.");
        Console.WriteLine(
            $"Totals: users={await db.Users.CountAsync(cancellationToken)}, " +
            $"cities={await db.Cities.CountAsync(cancellationToken)}, " +
            $"stores={await db.Stores.CountAsync(cancellationToken)}, " +
            $"products={await db.Products.CountAsync(cancellationToken)}, " +
            $"prices={await db.PriceEntries.CountAsync(cancellationToken)}");

        return 0;
    }
}
