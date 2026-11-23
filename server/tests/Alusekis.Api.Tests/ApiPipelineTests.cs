using System.Net;
using System.Net.Http.Json;
using Alusekis.Api.Api;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace Alusekis.Api.Tests;

public sealed class ApiPipelineTests : IDisposable
{
    private readonly TestDatabase _database = new();

    public void Dispose() => _database.Dispose();

    [Fact]
    public async Task Health_reports_server_and_database_healthy()
    {
        await using var factory = new ApiFactory(_database.ConnectionString);
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/health");
        var body = await response.Content.ReadFromJsonAsync<HealthBody>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", body!.Status);
        Assert.Equal("Healthy", body.Checks["server"].Status);
        Assert.Equal("Healthy", body.Checks["database"].Status);
    }

    [Fact]
    public async Task Unknown_route_returns_error_dto_with_request_id()
    {
        await using var factory = new ApiFactory(_database.ConnectionString);
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/v1/does-not-exist");
        var error = await response.Content.ReadFromJsonAsync<ErrorDto>();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType!.MediaType);
        Assert.Equal("utf-8", response.Content.Headers.ContentType.CharSet);
        Assert.Equal(ErrorCodes.NotFound, error!.Code);
        Assert.False(string.IsNullOrWhiteSpace(error.Message));
        Assert.Equal(response.Headers.GetValues(ApiPipeline.RequestIdHeader).Single(), error.RequestId);
    }

    [Fact]
    public async Task Ping_is_served_under_api_v1()
    {
        await using var factory = new ApiFactory(_database.ConnectionString);
        using var client = factory.CreateClient();

        var ping = await client.GetFromJsonAsync<PingResponse>("/api/v1/ping");

        Assert.Equal("ok", ping!.Status);
        Assert.Equal(DateTimeKind.Utc, ping.ServerTime.Kind);
    }

    [Fact]
    public void Missing_connection_string_fails_startup()
    {
        using var factory = new ApiFactory(connectionString: "");

        var ex = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("ConnectionStrings:Default", Flatten(ex));
    }

    private static string Flatten(Exception ex) =>
        ex is AggregateException agg
            ? string.Join(" | ", agg.Flatten().InnerExceptions.Select(Flatten))
            : ex.Message + (ex.InnerException is null ? "" : " | " + Flatten(ex.InnerException));

    private sealed class ApiFactory(string connectionString) : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = connectionString,
                ["Database:MigrateOnStartup"] = "false", // TestDatabase is already migrated
            }));
        }
    }

    private sealed record HealthBody(string Status, Dictionary<string, HealthEntry> Checks);

    private sealed record HealthEntry(string Status, string? Description);
}
