using Alusekis.Api.Api;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAlusekisApi();

var app = builder.Build();

app.UseAlusekisApi();
app.MapApiV1();

app.Run();

/// <summary>Entry point; public so integration tests can use WebApplicationFactory.</summary>
public partial class Program;
