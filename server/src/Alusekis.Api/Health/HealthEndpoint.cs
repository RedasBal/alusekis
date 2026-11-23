using Alusekis.Api.Data;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Alusekis.Api.Health;

public static class HealthEndpoint
{
    public const string Path = "/health";

    public static IServiceCollection AddAlusekisHealthChecks(this IServiceCollection services)
    {
        services.AddHealthChecks()
            .AddCheck("server", () => HealthCheckResult.Healthy())
            .AddCheck<DatabaseHealthCheck>("database");
        return services;
    }

    /// <summary>GET /health → 200 when healthy, 503 otherwise.</summary>
    public static IEndpointConventionBuilder MapAlusekisHealth(this IEndpointRouteBuilder endpoints) =>
        endpoints.MapHealthChecks(Path, new HealthCheckOptions { ResponseWriter = WriteResponseAsync });

    private static Task WriteResponseAsync(HttpContext context, HealthReport report)
    {
        var response = new HealthResponse(
            report.Status.ToString(),
            report.Entries.ToDictionary(
                e => e.Key,
                e => new HealthCheckEntry(e.Value.Status.ToString(), e.Value.Description)),
            DateTime.UtcNow);

        return context.Response.WriteAsJsonAsync(response, context.RequestAborted);
    }
}

public sealed record HealthResponse(string Status, IReadOnlyDictionary<string, HealthCheckEntry> Checks, DateTime CheckedAt);

public sealed record HealthCheckEntry(string Status, string? Description);

/// <summary>Healthy when the database is reachable and its schema has no pending migrations.</summary>
internal sealed class DatabaseHealthCheck(AppDbContext db, ILogger<DatabaseHealthCheck> logger) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            if (!await db.Database.CanConnectAsync(cancellationToken))
            {
                return HealthCheckResult.Unhealthy("Database is not reachable.");
            }

            var pending = (await db.Database.GetPendingMigrationsAsync(cancellationToken)).Count();
            return pending == 0
                ? HealthCheckResult.Healthy("Database is reachable and up to date.")
                : HealthCheckResult.Unhealthy($"Database schema is out of date ({pending} pending migration(s)).");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Details go to the log only; the endpoint is public.
            logger.LogError(ex, "Database health check failed");
            return HealthCheckResult.Unhealthy("Database check failed.");
        }
    }
}
