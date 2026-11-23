using Alusekis.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Alusekis.Api.Configuration;

public static class ConfigurationSetup
{
    /// <summary>
    /// Binds and validates settings (appsettings*.json overridden by environment variables)
    /// and registers the database. A missing required setting fails startup.
    /// </summary>
    public static IServiceCollection AddAlusekisConfiguration(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<DatabaseOptions>()
            .Bind(configuration.GetSection(DatabaseOptions.SectionName))
            .Configure(options => options.ConnectionString =
                configuration.GetConnectionString(DatabaseOptions.ConnectionStringName) ?? string.Empty)
            .ValidateDataAnnotations()
            .ValidateOnStart();

        services.AddDbContext<AppDbContext>((provider, options) =>
            options.UseAlusekisSqlite(provider.GetRequiredService<IOptions<DatabaseOptions>>().Value.ConnectionString));

        return services;
    }

    /// <summary>
    /// Validates required settings immediately (also for CLI modes that never start the web host)
    /// and applies migrations when <see cref="DatabaseOptions.MigrateOnStartup"/> is set.
    /// </summary>
    public static async Task PrepareDatabaseAsync(this IServiceProvider services, bool forceMigrate = false)
    {
        var options = services.GetRequiredService<IOptions<DatabaseOptions>>().Value;

        if (!options.MigrateOnStartup && !forceMigrate)
        {
            return;
        }

        await using var scope = services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }
}
