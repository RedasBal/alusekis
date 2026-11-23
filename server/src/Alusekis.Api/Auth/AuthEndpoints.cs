using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Alusekis.Api.Auth;

public sealed record RegisterRequest(string? Email, string? Password);

public sealed record LoginRequest(string? Email, string? Password);

public sealed record ForgotPasswordRequest(string? Email);

public sealed record ResetPasswordRequest(string? Token, string? NewPassword);

public sealed record DeleteAccountRequest(string? Password);

public sealed record UserDto(long Id, string Email, string DisplayName, Role Role);

public sealed record AuthResponse(UserDto User, string Token, DateTime ExpiresAt);

/// <summary>Account endpoints under <c>/api/v1/auth</c>.</summary>
public static class AuthEndpoints
{
    // Verified against when the account does not exist, so response time does not reveal it.
    private static readonly User DummyUser = new() { Email = "", NormalizedEmail = "", DisplayName = "" };
    private static readonly string DummyHash = new PasswordHasher<User>().HashPassword(DummyUser, "alusekis-dummy-password");

    public static RouteGroupBuilder MapAuth(this RouteGroupBuilder v1)
    {
        var auth = v1.MapGroup("/auth");

        auth.MapPost("/register", Register);
        auth.MapPost("/login", Login);
        auth.MapPost("/forgot-password", ForgotPassword);
        auth.MapPost("/reset-password", ResetPassword);

        auth.MapPost("/logout", Logout).RequireAuthorization();
        auth.MapGet("/me", Me).RequireAuthorization();
        auth.MapDelete("/account", DeleteAccount).RequireAuthorization();

        return v1;
    }

    private static async Task<IResult> Register(
        RegisterRequest request,
        HttpContext http,
        AppDbContext db,
        IPasswordHasher<User> hasher,
        TimeProvider clock,
        CancellationToken ct)
    {
        if (!AuthRules.TryNormalizeEmail(request.Email, out var normalized))
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.EmailInvalid,
                "The e-mail address is not valid (at most 254 characters).");
        }

        if (!AuthRules.IsValidPassword(request.Password))
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.PasswordLengthInvalid,
                $"The password must be {AuthRules.MinPasswordLength}-{AuthRules.MaxPasswordLength} characters long.");
        }

        if (await db.Users.AnyAsync(u => u.NormalizedEmail == normalized, ct))
        {
            return EmailTaken(http);
        }

        var now = clock.GetUtcNow().UtcDateTime;
        var user = new User
        {
            Email = request.Email!.Trim(),
            NormalizedEmail = normalized,
            DisplayName = DisplayNameFrom(normalized),
            Role = Role.User,
            CreatedAt = now,
        };
        user.PasswordHash = hasher.HashPassword(user, request.Password!);

        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        db.Users.Add(user);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (IsUniqueViolation(ex))
        {
            return EmailTaken(http); // lost a race with a concurrent registration
        }

        var (token, session) = NewSession(user.Id, now);
        db.Sessions.Add(session);
        db.AuditEntries.Add(new AuditEntry
        {
            ActorUserId = user.Id,
            Action = AuditActions.AccountRegistered,
            EntityType = nameof(User),
            EntityId = user.Id,
            CreatedAt = now,
        });
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return Results.Json(ToResponse(user, token, session), statusCode: StatusCodes.Status201Created);
    }

    private static async Task<IResult> Login(
        LoginRequest request,
        HttpContext http,
        AppDbContext db,
        IPasswordHasher<User> hasher,
        LoginAttemptLimiter limiter,
        TimeProvider clock,
        CancellationToken ct)
    {
        // One answer for every failure so the response never says which field was wrong.
        IResult Invalid() => Error(http, StatusCodes.Status401Unauthorized, ErrorCodes.InvalidCredentials,
            "The e-mail or password is incorrect.");

        if (!AuthRules.TryNormalizeEmail(request.Email, out var normalized))
        {
            return Invalid();
        }

        if (IsLockedOut(http, limiter, normalized) is { } locked)
        {
            return locked;
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.NormalizedEmail == normalized, ct);
        var password = request.Password ?? string.Empty;
        var rehash = false;
        var verified = password.Length <= AuthRules.MaxPasswordLength
            && VerifyPassword(hasher, user, password, out rehash);

        if (!verified || user is null)
        {
            limiter.RecordFailure(normalized);
            return Invalid();
        }

        limiter.Reset(normalized);
        var now = clock.GetUtcNow().UtcDateTime;

        if (rehash)
        {
            user.PasswordHash = hasher.HashPassword(user, password);
        }

        var (token, session) = NewSession(user.Id, now);
        db.Sessions.Add(session);
        await db.SaveChangesAsync(ct);

        return Results.Ok(ToResponse(user, token, session));
    }

    private static async Task<IResult> Logout(HttpContext http, AppDbContext db, TimeProvider clock, CancellationToken ct)
    {
        var sessionId = http.User.GetSessionId();
        var now = (DateTime?)clock.GetUtcNow().UtcDateTime;

        await db.Sessions
            .Where(s => s.Id == sessionId && s.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, now), ct);

        return Results.NoContent();
    }

    private static async Task<IResult> Me(HttpContext http, AppDbContext db, CancellationToken ct)
    {
        var userId = http.User.GetUserId();
        var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == userId, ct);

        return user is null
            ? Error(http, StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized, "Unauthorized.")
            : Results.Ok(ToDto(user));
    }

    /// <summary>
    /// Always answers 202, whether or not the address belongs to an account, so it cannot be
    /// used to find out who is registered.
    /// </summary>
    private static async Task<IResult> ForgotPassword(
        ForgotPasswordRequest request,
        HttpContext http,
        AppDbContext db,
        IEmailSender emailSender,
        IOptions<AuthOptions> options,
        TimeProvider clock,
        ILoggerFactory loggerFactory,
        CancellationToken ct)
    {
        if (!AuthRules.TryNormalizeEmail(request.Email, out var normalized))
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.EmailInvalid,
                "The e-mail address is not valid (at most 254 characters).");
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.NormalizedEmail == normalized, ct);
        if (user is null)
        {
            return Results.Accepted();
        }

        var token = Tokens.Generate();
        user.PasswordResetTokenHash = Tokens.Hash(token);
        user.PasswordResetExpiresAt = clock.GetUtcNow().UtcDateTime + AuthRules.PasswordResetLifetime;
        await db.SaveChangesAsync(ct);

        var link = $"{options.Value.ResetLinkBaseUrl}?token={Uri.EscapeDataString(token)}";
        try
        {
            await emailSender.SendPasswordResetAsync(user.Email, link, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Do not let a mail failure reveal that the account exists.
            loggerFactory.CreateLogger("Alusekis.Auth")
                .LogError(ex, "Sending the password reset e-mail failed for request {RequestId}", http.TraceIdentifier);
        }

        return Results.Accepted();
    }

    private static async Task<IResult> ResetPassword(
        ResetPasswordRequest request,
        HttpContext http,
        AppDbContext db,
        IPasswordHasher<User> hasher,
        LoginAttemptLimiter limiter,
        TimeProvider clock,
        CancellationToken ct)
    {
        IResult InvalidToken() => Error(http, StatusCodes.Status400BadRequest, ErrorCodes.InvalidResetToken,
            "The reset token is invalid, expired or already used.");

        var token = request.Token?.Trim();
        if (string.IsNullOrEmpty(token) || token.Length > 256)
        {
            return InvalidToken();
        }

        if (!AuthRules.IsValidPassword(request.NewPassword))
        {
            return Error(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.PasswordLengthInvalid,
                $"The password must be {AuthRules.MinPasswordLength}-{AuthRules.MaxPasswordLength} characters long.");
        }

        var hash = Tokens.Hash(token);
        var now = clock.GetUtcNow().UtcDateTime;

        var user = await db.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.PasswordResetTokenHash == hash && u.PasswordResetExpiresAt > now, ct);
        if (user is null)
        {
            return InvalidToken();
        }

        var newHash = hasher.HashPassword(user, request.NewPassword!);
        var revokedAt = (DateTime?)now;

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Single use: the conditional update succeeds for exactly one of any concurrent requests.
        var consumed = await db.Users
            .Where(u => u.Id == user.Id && u.PasswordResetTokenHash == hash)
            .ExecuteUpdateAsync(s => s
                .SetProperty(u => u.PasswordHash, newHash)
                .SetProperty(u => u.PasswordResetTokenHash, (string?)null)
                .SetProperty(u => u.PasswordResetExpiresAt, (DateTime?)null), ct);
        if (consumed == 0)
        {
            return InvalidToken();
        }

        // A new password signs the account out everywhere.
        await db.Sessions
            .Where(s => s.UserId == user.Id && s.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, revokedAt), ct);

        await transaction.CommitAsync(ct);
        limiter.Reset(user.NormalizedEmail);

        return Results.NoContent();
    }

    private static async Task<IResult> DeleteAccount(
        [FromBody] DeleteAccountRequest request,
        HttpContext http,
        AppDbContext db,
        IPasswordHasher<User> hasher,
        LoginAttemptLimiter limiter,
        TimeProvider clock,
        CancellationToken ct)
    {
        var userId = http.User.GetUserId();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);
        if (user is null)
        {
            return Error(http, StatusCodes.Status401Unauthorized, ErrorCodes.Unauthorized, "Unauthorized.");
        }

        if (IsLockedOut(http, limiter, user.NormalizedEmail) is { } locked)
        {
            return locked;
        }

        var password = request.Password ?? string.Empty;
        if (password.Length > AuthRules.MaxPasswordLength || !VerifyPassword(hasher, user, password, out _))
        {
            limiter.RecordFailure(user.NormalizedEmail);
            // 403, not 401: the session is fine, so the client must not sign the user out.
            return Error(http, StatusCodes.Status403Forbidden, ErrorCodes.InvalidPassword, "The password is incorrect.");
        }

        var now = clock.GetUtcNow().UtcDateTime;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Public data stays, but no longer points at the person.
        await db.PriceEntries.Where(p => p.SubmittedByUserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.SubmittedByUserId, (long?)null), ct);
        await db.Products.Where(p => p.CreatedByUserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.CreatedByUserId, (long?)null), ct);
        await db.Reports.Where(r => r.ReporterUserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(r => r.ReporterUserId, (long?)null), ct);
        await db.Reports.Where(r => r.ResolvedByUserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(r => r.ResolvedByUserId, (long?)null), ct);
        await db.AuditEntries.Where(a => a.ActorUserId == userId)
            .ExecuteUpdateAsync(s => s.SetProperty(a => a.ActorUserId, (long?)null), ct);

        await db.Sessions.Where(s => s.UserId == userId).ExecuteDeleteAsync(ct);
        await db.RequestResults.Where(r => r.UserId == userId).ExecuteDeleteAsync(ct);
        await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync(ct);

        // Neither record contains an e-mail address or any other personal data.
        db.DeletionMarkers.Add(new DeletionMarker { EntityType = nameof(User), EntityId = userId, DeletedAt = now });
        db.AuditEntries.Add(new AuditEntry
        {
            ActorUserId = null,
            Action = AuditActions.AccountDeleted,
            EntityType = nameof(User),
            EntityId = userId,
            CreatedAt = now,
        });
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        limiter.Reset(user.NormalizedEmail);
        return Results.NoContent();
    }

    private static IResult? IsLockedOut(HttpContext http, LoginAttemptLimiter limiter, string key)
    {
        if (!limiter.IsLocked(key, out var retryAfter))
        {
            return null;
        }

        http.Response.Headers.RetryAfter = ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(System.Globalization.CultureInfo.InvariantCulture);
        return Error(http, StatusCodes.Status429TooManyRequests, ErrorCodes.TooManyRequests,
            "Too many failed attempts. Try again later.");
    }

    private static bool VerifyPassword(IPasswordHasher<User> hasher, User? user, string password, out bool rehashNeeded)
    {
        rehashNeeded = false;
        if (user?.PasswordHash is null)
        {
            hasher.VerifyHashedPassword(DummyUser, DummyHash, password);
            return false;
        }

        var result = hasher.VerifyHashedPassword(user, user.PasswordHash, password);
        rehashNeeded = result == PasswordVerificationResult.SuccessRehashNeeded;
        return result != PasswordVerificationResult.Failed;
    }

    private static (string Token, Session Session) NewSession(long userId, DateTime now)
    {
        var token = Tokens.Generate();
        var session = new Session
        {
            UserId = userId,
            TokenHash = Tokens.Hash(token),
            CreatedAt = now,
            ExpiresAt = now + AuthRules.SessionLifetime,
        };
        return (token, session);
    }

    private static AuthResponse ToResponse(User user, string token, Session session) =>
        new(ToDto(user), token, session.ExpiresAt);

    private static UserDto ToDto(User user) => new(user.Id, user.Email, user.DisplayName, user.Role);

    private static string DisplayNameFrom(string normalizedEmail)
    {
        var local = normalizedEmail[..normalizedEmail.IndexOf('@')];
        return local.Length <= 100 ? local : local[..100];
    }

    private static IResult EmailTaken(HttpContext http) =>
        Error(http, StatusCodes.Status409Conflict, ErrorCodes.EmailTaken, "This e-mail address is already registered.");

    private static IResult Error(HttpContext http, int status, string code, string message) =>
        ErrorResponses.Result(http, status, code, message);

    private static bool IsUniqueViolation(DbUpdateException ex) =>
        ex.InnerException is SqliteException { SqliteErrorCode: 19 } sqlite
        && sqlite.Message.Contains("UNIQUE", StringComparison.OrdinalIgnoreCase);
}
