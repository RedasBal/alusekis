using System.Security.Claims;
using System.Text.Encodings.Web;
using Alusekis.Api.Data;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Alusekis.Api.Auth;

public static class AuthClaims
{
    public const string SessionId = "alusekis:session-id";

    public static long GetUserId(this ClaimsPrincipal principal) =>
        long.Parse(principal.FindFirstValue(ClaimTypes.NameIdentifier)!, System.Globalization.CultureInfo.InvariantCulture);

    public static long GetSessionId(this ClaimsPrincipal principal) =>
        long.Parse(principal.FindFirstValue(SessionId)!, System.Globalization.CultureInfo.InvariantCulture);
}

/// <summary>
/// Validates <c>Authorization: Bearer &lt;token&gt;</c> against the Sessions table on every
/// request: the token hash must exist, not be revoked and not be expired.
/// </summary>
internal sealed class SessionAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    AppDbContext db,
    TimeProvider clock) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private const string BearerPrefix = "Bearer ";
    private const int MaxTokenLength = 256;

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith(BearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return AuthenticateResult.NoResult();
        }

        var token = header[BearerPrefix.Length..].Trim();
        if (token.Length is 0 or > MaxTokenLength)
        {
            return AuthenticateResult.Fail("Malformed token.");
        }

        var hash = Tokens.Hash(token);
        var now = clock.GetUtcNow().UtcDateTime;

        var session = await db.Sessions
            .AsNoTracking()
            .Where(s => s.TokenHash == hash && s.RevokedAt == null && s.ExpiresAt > now)
            .Select(s => new { s.Id, s.UserId, s.User.Role })
            .FirstOrDefaultAsync(Context.RequestAborted);

        if (session is null)
        {
            return AuthenticateResult.Fail("Unknown, expired or revoked session.");
        }

        var identity = new ClaimsIdentity(
            [
                new Claim(ClaimTypes.NameIdentifier, session.UserId.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                new Claim(ClaimTypes.Role, session.Role.ToString()),
                new Claim(AuthClaims.SessionId, session.Id.ToString(System.Globalization.CultureInfo.InvariantCulture)),
            ],
            Scheme.Name);

        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name));
    }
}
