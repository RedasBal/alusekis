using System.Net.Mail;
using Alusekis.Api.Domain;

namespace Alusekis.Api.Auth;

/// <summary>Limits and validation shared by all authentication endpoints.</summary>
public static class AuthRules
{
    public const string SchemeName = "Session";

    public const int MaxEmailLength = 254;
    public const int MinPasswordLength = 12;
    public const int MaxPasswordLength = 128;

    /// <summary>Access token lifetime (absolute, not sliding). Must stay at most 30 minutes.</summary>
    public static readonly TimeSpan SessionLifetime = TimeSpan.FromMinutes(30);

    public static readonly TimeSpan PasswordResetLifetime = TimeSpan.FromMinutes(30);

    /// <summary>Failed attempts allowed per account within <see cref="FailedLoginWindow"/>.</summary>
    public const int MaxFailedLogins = 5;

    public static readonly TimeSpan FailedLoginWindow = TimeSpan.FromMinutes(15);

    /// <summary>Normalizes and validates an e-mail address (at most 254 characters, plain address form).</summary>
    public static bool TryNormalizeEmail(string? raw, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(raw) || raw.Trim().Length > MaxEmailLength)
        {
            return false;
        }

        var candidate = TextNormalizer.NormalizeEmail(raw);
        if (!MailAddress.TryCreate(candidate, out var address)
            || address.Address != candidate
            || !address.Host.Contains('.'))
        {
            return false;
        }

        normalized = candidate;
        return true;
    }

    public static bool IsValidPassword(string? password) =>
        password is { Length: >= MinPasswordLength and <= MaxPasswordLength };
}

/// <summary>Role-based authorization policies. Guest = not signed in; checked only on the server.</summary>
public static class Policies
{
    /// <summary>Signed in as User or Admin: may change data.</summary>
    public const string User = "RequireUser";

    /// <summary>Signed in as Admin: manages the catalog.</summary>
    public const string Admin = "RequireAdmin";
}

public static class AuditActions
{
    public const string AccountRegistered = "account.registered";
    public const string AccountDeleted = "account.deleted";
}
