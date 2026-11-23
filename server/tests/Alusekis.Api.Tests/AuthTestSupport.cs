using Alusekis.Api.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Alusekis.Api.Tests;

/// <summary>Clock the tests can move forward (token expiry, lock-out window).</summary>
internal sealed class FakeClock : TimeProvider
{
    private DateTimeOffset _now = new(2026, 11, 23, 12, 0, 0, TimeSpan.Zero);

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan by) => _now += by;
}

/// <summary>Collects "sent" e-mails so tests can read the reset link.</summary>
internal sealed class CapturingEmailSender : IEmailSender
{
    private readonly List<(string To, string Link)> _sent = [];

    public IReadOnlyList<(string To, string Link)> Sent
    {
        get
        {
            lock (_sent)
            {
                return [.. _sent];
            }
        }
    }

    public Task SendPasswordResetAsync(string toEmail, string resetLink, CancellationToken cancellationToken)
    {
        lock (_sent)
        {
            _sent.Add((toEmail, resetLink));
        }

        return Task.CompletedTask;
    }

    public string LastToken()
    {
        var link = Sent[^1].Link;
        return Uri.UnescapeDataString(link[(link.IndexOf("token=", StringComparison.Ordinal) + "token=".Length)..]);
    }
}

internal sealed class AuthApiFactory(string connectionString, FakeClock clock, CapturingEmailSender mail)
    : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:Default"] = connectionString,
            ["Database:MigrateOnStartup"] = "false", // TestDatabase is already migrated
        }));
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<TimeProvider>();
            services.AddSingleton<TimeProvider>(clock);
            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender>(mail);
        });
    }
}
