using Alusekis.Api.Api;
using Alusekis.Api.Configuration;
using Alusekis.Api.Health;
using Alusekis.Api.Seeding;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAlusekisConfiguration(builder.Configuration);
builder.Services.AddAlusekisApi();
builder.Services.AddAlusekisHealthChecks();
builder.Services.AddScoped<DataSeeder>();

var app = builder.Build();

// CLI mode: `dotnet run -- seed` seeds the database and exits.
if (SeedCommand.IsRequested(args))
{
    return await SeedCommand.RunAsync(app.Services);
}

// Fails fast with a clear message if a required setting is missing.
await app.Services.PrepareDatabaseAsync();

app.UseAlusekisApi();
app.MapApiV1();
app.MapAlusekisHealth();

await app.RunAsync();
return 0;

/// <summary>Entry point; public so integration tests can use WebApplicationFactory.</summary>
public partial class Program;
