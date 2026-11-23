using Alusekis.Api.Domain;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Alusekis.Api.Auth;

public sealed class AuthOptions
{
    public const string SectionName = "Auth";

    /// <summary>Base of the link put in the password reset e-mail; <c>?token=...</c> is appended.</summary>
    public string ResetLinkBaseUrl { get; set; } = "alusekis://reset-password";
}

public static class AuthSetup
{
    public static IServiceCollection AddAlusekisAuth(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<AuthOptions>(configuration.GetSection(AuthOptions.SectionName));

        // Adaptive, salted hashing (PBKDF2 with per-password salt and versioned format).
        services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();
        services.AddSingleton<LoginAttemptLimiter>();
        services.TryAddSingleton<IEmailSender, ConsoleEmailSender>();

        services.AddAuthentication(AuthRules.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, SessionAuthenticationHandler>(AuthRules.SchemeName, null);

        services.AddAuthorizationBuilder()
            .AddPolicy(Policies.User, policy => policy
                .RequireAuthenticatedUser()
                .RequireRole(nameof(Role.User), nameof(Role.Admin)))
            .AddPolicy(Policies.Admin, policy => policy
                .RequireAuthenticatedUser()
                .RequireRole(nameof(Role.Admin)));

        return services;
    }
}
