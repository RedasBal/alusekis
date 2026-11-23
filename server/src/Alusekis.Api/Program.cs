using Alusekis.Api.Api;
using Alusekis.Api.Configuration;
using Alusekis.Api.Health;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAlusekisConfiguration(builder.Configuration);
builder.Services.AddAlusekisApi();
builder.Services.AddAlusekisHealthChecks();

var app = builder.Build();

// Fails fast with a clear message if a required setting is missing.
await app.Services.PrepareDatabaseAsync();

app.UseAlusekisApi();
app.MapApiV1();
app.MapAlusekisHealth();

await app.RunAsync();

/// <summary>Entry point; public so integration tests can use WebApplicationFactory.</summary>
public partial class Program;
