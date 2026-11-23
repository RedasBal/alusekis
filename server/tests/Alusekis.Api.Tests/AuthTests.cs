using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Seeding;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Alusekis.Api.Tests;

public sealed class AuthTests : IDisposable
{
    private const string Email = "jonas@example.lt";
    private const string Password = "correct horse battery";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly CapturingEmailSender _mail = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;

    public AuthTests()
    {
        _factory = new AuthApiFactory(_database.ConnectionString, _clock, _mail);
        _client = _factory.CreateClient();
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        _database.Dispose();
    }

    // ---------- registration ----------

    [Fact]
    public async Task Register_creates_account_and_returns_token()
    {
        var response = await Send(HttpMethod.Post, "/api/v1/auth/register", new { email = Email, password = Password });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ReadAuth(response);
        Assert.Equal(Email, body.User.Email);
        Assert.Equal(Role.User, body.User.Role);
        Assert.False(string.IsNullOrWhiteSpace(body.Token));
        Assert.True(body.ExpiresAt <= _clock.GetUtcNow().UtcDateTime.AddMinutes(30));
        Assert.Equal(DateTimeKind.Utc, body.ExpiresAt.Kind);
    }

    [Fact]
    public async Task Two_different_emails_can_register()
    {
        Assert.Equal(HttpStatusCode.Created, (await Register("one@example.lt")).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Register("two@example.lt")).StatusCode);
    }

    [Theory]
    [InlineData("jonas@example.lt")]
    [InlineData("  JONAS@Example.LT ")]
    public async Task Register_with_existing_email_is_rejected(string secondAttempt)
    {
        Assert.Equal(HttpStatusCode.Created, (await Register(Email)).StatusCode);

        var response = await Register(secondAttempt);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal(ErrorCodes.EmailTaken, (await ReadError(response)).Code);
        await using var db = _database.CreateContext();
        Assert.Equal(1, await db.Users.CountAsync());
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-an-email")]
    [InlineData("a@b")]
    [InlineData("Jonas <jonas@example.lt>")]
    [InlineData("jo nas@example.lt")]
    public async Task Register_with_invalid_email_is_rejected(string email)
    {
        var response = await Register(email);

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.EmailInvalid, (await ReadError(response)).Code);
    }

    [Fact]
    public async Task Register_with_email_over_254_characters_is_rejected()
    {
        var response = await Register(new string('a', 250) + "@x.lt");

        Assert.Equal(ErrorCodes.EmailInvalid, (await ReadError(response)).Code);
    }

    [Fact]
    public async Task Register_accepts_email_of_exactly_254_characters()
    {
        var local = new string('a', 64);
        var email = $"{local}@{new string('b', 63)}.{new string('c', 63)}.{new string('d', 58)}.lt";
        Assert.Equal(254, email.Length);

        var response = await Register(email);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Theory]
    [InlineData(11)]
    [InlineData(129)]
    public async Task Register_with_password_outside_12_to_128_is_rejected(int length)
    {
        var response = await Register(Email, new string('x', length));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.PasswordLengthInvalid, (await ReadError(response)).Code);
    }

    [Theory]
    [InlineData(12)]
    [InlineData(128)]
    public async Task Register_accepts_password_boundaries(int length)
    {
        var response = await Register(Email, new string('x', length));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task Register_with_empty_body_returns_error_dto()
    {
        var response = await _client.PostAsync(
            "/api/v1/auth/register", new StringContent("", Encoding.UTF8, "application/json"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.False(string.IsNullOrEmpty((await ReadError(response)).RequestId));
    }

    [Fact]
    public async Task Passwords_and_tokens_are_stored_only_as_hashes()
    {
        var auth = await ReadAuth(await Register(Email));

        await using var db = _database.CreateContext();
        var user = await db.Users.SingleAsync();
        Assert.NotEqual(Password, user.PasswordHash);
        Assert.DoesNotContain(Password, user.PasswordHash);
        var verify = new PasswordHasher<User>().VerifyHashedPassword(user, user.PasswordHash!, Password);
        Assert.NotEqual(PasswordVerificationResult.Failed, verify);

        var session = await db.Sessions.SingleAsync();
        Assert.NotEqual(auth.Token, session.TokenHash);
        Assert.Equal(Tokens.Hash(auth.Token), session.TokenHash);
        Assert.Equal(64, session.TokenHash.Length);
        Assert.True(session.ExpiresAt - session.CreatedAt <= TimeSpan.FromMinutes(30));
    }

    [Fact]
    public async Task Registration_is_audited_without_secrets()
    {
        var auth = await ReadAuth(await Register(Email));

        await using var db = _database.CreateContext();
        var entry = await db.AuditEntries.SingleAsync();
        Assert.Equal(AuditActions.AccountRegistered, entry.Action);
        Assert.Equal(auth.User.Id, entry.ActorUserId);
        var text = $"{entry.Action}|{entry.EntityType}|{entry.DetailsJson}";
        Assert.DoesNotContain(Email, text);
        Assert.DoesNotContain(Password, text);
        Assert.DoesNotContain(auth.Token, text);
    }

    // ---------- login ----------

    [Fact]
    public async Task Login_with_correct_credentials_returns_a_working_token()
    {
        await Register(Email);

        var response = await Login(Email, Password);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var auth = await ReadAuth(response);
        Assert.Equal(HttpStatusCode.OK, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);
    }

    [Fact]
    public async Task Login_failure_does_not_reveal_which_field_was_wrong()
    {
        await Register(Email);

        var wrongPassword = await Login(Email, "definitely not the password");
        var unknownEmail = await Login("nobody@example.lt", Password);

        Assert.Equal(HttpStatusCode.Unauthorized, wrongPassword.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, unknownEmail.StatusCode);
        var a = await ReadError(wrongPassword);
        var b = await ReadError(unknownEmail);
        Assert.Equal(ErrorCodes.InvalidCredentials, a.Code);
        Assert.Equal(a.Code, b.Code);
        Assert.Equal(a.Message, b.Message);
    }

    [Fact]
    public async Task Five_failed_logins_lock_the_account_for_15_minutes()
    {
        await Register(Email);

        for (var i = 0; i < 5; i++)
        {
            Assert.Equal(HttpStatusCode.Unauthorized, (await Login(Email, "wrong password!!")).StatusCode);
        }

        // Even the correct password is refused while locked.
        var locked = await Login(Email, Password);
        Assert.Equal(HttpStatusCode.TooManyRequests, locked.StatusCode);
        Assert.Equal(ErrorCodes.TooManyRequests, (await ReadError(locked)).Code);
        Assert.True(locked.Headers.RetryAfter?.Delta > TimeSpan.Zero);

        _clock.Advance(TimeSpan.FromMinutes(15) + TimeSpan.FromSeconds(1));

        Assert.Equal(HttpStatusCode.OK, (await Login(Email, Password)).StatusCode);
    }

    [Fact]
    public async Task Four_failed_logins_do_not_lock_the_account()
    {
        await Register(Email);

        for (var i = 0; i < 4; i++)
        {
            await Login(Email, "wrong password!!");
        }

        Assert.Equal(HttpStatusCode.OK, (await Login(Email, Password)).StatusCode);
    }

    [Fact]
    public async Task Lock_out_is_per_account()
    {
        await Register(Email);
        await Register("other@example.lt");

        for (var i = 0; i < 5; i++)
        {
            await Login(Email, "wrong password!!");
        }

        Assert.Equal(HttpStatusCode.OK, (await Login("other@example.lt", Password)).StatusCode);
    }

    // ---------- sessions ----------

    [Fact]
    public async Task Request_after_logout_is_rejected_and_session_is_revoked()
    {
        var auth = await ReadAuth(await Register(Email));
        Assert.Equal(HttpStatusCode.OK, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);

        var logout = await Send(HttpMethod.Post, "/api/v1/auth/logout", null, auth.Token);
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        var after = await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token);
        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
        Assert.Equal(ErrorCodes.Unauthorized, (await ReadError(after)).Code);

        await using var db = _database.CreateContext();
        Assert.NotNull((await db.Sessions.SingleAsync()).RevokedAt);
    }

    [Fact]
    public async Task Logout_only_ends_the_current_session()
    {
        var first = await ReadAuth(await Register(Email));
        var second = await ReadAuth(await Login(Email, Password));

        await Send(HttpMethod.Post, "/api/v1/auth/logout", null, first.Token);

        Assert.Equal(HttpStatusCode.Unauthorized, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, first.Token)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, second.Token)).StatusCode);
    }

    [Fact]
    public async Task Token_expires_after_30_minutes()
    {
        var auth = await ReadAuth(await Register(Email));

        _clock.Advance(TimeSpan.FromMinutes(29));
        Assert.Equal(HttpStatusCode.OK, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);

        _clock.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(HttpStatusCode.Unauthorized, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("garbage-token")]
    public async Task Protected_endpoints_reject_missing_or_unknown_tokens(string? token)
    {
        var response = await Send(HttpMethod.Get, "/api/v1/auth/me", null, token);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var error = await ReadError(response);
        Assert.Equal(ErrorCodes.Unauthorized, error.Code);
        Assert.Equal(response.Headers.GetValues(ApiPipeline.RequestIdHeader).Single(), error.RequestId);
    }

    // ---------- roles ----------

    [Theory]
    [InlineData(null, Policies.User, false)]
    [InlineData("Guest", Policies.User, false)]
    [InlineData("User", Policies.User, true)]
    [InlineData("Admin", Policies.User, true)]
    [InlineData(null, Policies.Admin, false)]
    [InlineData("Guest", Policies.Admin, false)]
    [InlineData("User", Policies.Admin, false)]
    [InlineData("Admin", Policies.Admin, true)]
    public async Task Role_policies_follow_guest_user_admin(string? role, string policy, bool expected)
    {
        _ = _client; // starts the host
        var authorization = _factory.Services.GetRequiredService<IAuthorizationService>();
        var identity = role is null
            ? new ClaimsIdentity()
            : new ClaimsIdentity([new Claim(ClaimTypes.Role, role)], "test");

        var result = await authorization.AuthorizeAsync(new ClaimsPrincipal(identity), null, policy);

        Assert.Equal(expected, result.Succeeded);
    }

    // ---------- password reset ----------

    [Fact]
    public async Task Forgot_password_sends_link_and_stores_only_the_token_hash()
    {
        await Register(Email);

        var response = await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = Email });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        var sent = Assert.Single(_mail.Sent);
        Assert.Equal(Email, sent.To);
        var token = _mail.LastToken();
        Assert.False(string.IsNullOrEmpty(token));

        await using var db = _database.CreateContext();
        var user = await db.Users.SingleAsync();
        Assert.Equal(Tokens.Hash(token), user.PasswordResetTokenHash);
        Assert.NotEqual(token, user.PasswordResetTokenHash);
        Assert.True(user.PasswordResetExpiresAt <= _clock.GetUtcNow().UtcDateTime.AddMinutes(30));
    }

    [Fact]
    public async Task Forgot_password_looks_the_same_for_unknown_email_and_sends_nothing()
    {
        var response = await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = "nobody@example.lt" });

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Empty(_mail.Sent);
    }

    [Fact]
    public async Task Reset_token_works_exactly_once()
    {
        await Register(Email);
        await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = Email });
        var token = _mail.LastToken();
        const string newPassword = "a brand new password";

        var first = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token, newPassword });
        var second = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token, newPassword = "yet another password" });

        Assert.Equal(HttpStatusCode.NoContent, first.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, second.StatusCode);
        Assert.Equal(ErrorCodes.InvalidResetToken, (await ReadError(second)).Code);

        Assert.Equal(HttpStatusCode.OK, (await Login(Email, newPassword)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Login(Email, Password)).StatusCode);
        await using var db = _database.CreateContext();
        Assert.Null((await db.Users.SingleAsync()).PasswordResetTokenHash);
    }

    [Fact]
    public async Task Reset_token_expires_after_30_minutes()
    {
        await Register(Email);
        await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = Email });
        var token = _mail.LastToken();

        _clock.Advance(TimeSpan.FromMinutes(31));
        var response = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token, newPassword = "a brand new password" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(ErrorCodes.InvalidResetToken, (await ReadError(response)).Code);
    }

    [Fact]
    public async Task Reset_with_unknown_token_or_short_password_is_rejected()
    {
        await Register(Email);
        await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = Email });

        var unknown = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token = "nope", newPassword = "a brand new password" });
        var shortPassword = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token = _mail.LastToken(), newPassword = "short" });

        Assert.Equal(ErrorCodes.InvalidResetToken, (await ReadError(unknown)).Code);
        Assert.Equal(ErrorCodes.PasswordLengthInvalid, (await ReadError(shortPassword)).Code);
        // A rejected password does not burn the token.
        var ok = await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token = _mail.LastToken(), newPassword = "a brand new password" });
        Assert.Equal(HttpStatusCode.NoContent, ok.StatusCode);
    }

    [Fact]
    public async Task Reset_signs_out_existing_sessions()
    {
        var auth = await ReadAuth(await Register(Email));
        await Send(HttpMethod.Post, "/api/v1/auth/forgot-password", new { email = Email });

        await Send(HttpMethod.Post, "/api/v1/auth/reset-password", new { token = _mail.LastToken(), newPassword = "a brand new password" });

        Assert.Equal(HttpStatusCode.Unauthorized, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);
    }

    // ---------- account deletion ----------

    [Fact]
    public async Task Delete_with_wrong_password_keeps_the_account_and_the_session()
    {
        var auth = await ReadAuth(await Register(Email));

        var response = await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = "not my password!" }, auth.Token);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(ErrorCodes.InvalidPassword, (await ReadError(response)).Code);
        await using var db = _database.CreateContext();
        Assert.Equal(1, await db.Users.CountAsync());
        Assert.Equal(HttpStatusCode.OK, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);
    }

    [Fact]
    public async Task Delete_requires_authentication()
    {
        var response = await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = Password });

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Delete_removes_account_and_sessions_but_keeps_public_data_unlinked()
    {
        long priceId;
        long reportId;
        long productId;
        await using (var seedDb = _database.CreateContext())
        {
            await new DataSeeder(seedDb).SeedAsync();
        }

        var auth = await ReadAuth(await Register(Email));
        var second = await ReadAuth(await Login(Email, Password));
        var userId = auth.User.Id;

        await using (var db = _database.CreateContext())
        {
            var product = await db.Products.FirstAsync();
            var store = await db.Stores.FirstAsync();
            var price = new PriceEntry
            {
                ProductId = product.Id,
                StoreId = store.Id,
                SubmittedByUserId = userId,
                PriceCents = 199,
                Status = PriceStatus.Approved,
                ObservedAt = _clock.GetUtcNow().UtcDateTime,
                CreatedAt = _clock.GetUtcNow().UtcDateTime,
            };
            var created = new Product
            {
                Name = "Mano produktas",
                NormalizedName = "mano produktas",
                VolumeMl = 330,
                CreatedByUserId = userId,
                CreatedAt = _clock.GetUtcNow().UtcDateTime,
            };
            db.AddRange(price, created);
            await db.SaveChangesAsync();
            var report = new Report
            {
                PriceEntryId = price.Id,
                ReporterUserId = userId,
                Reason = ReportReason.WrongPrice,
                SubmittedAt = _clock.GetUtcNow().UtcDateTime,
            };
            db.Reports.Add(report);
            await db.SaveChangesAsync();
            priceId = price.Id;
            productId = created.Id;
            reportId = report.Id;
        }

        var response = await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = Password }, auth.Token);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        await using var verify = _database.CreateContext();
        Assert.False(await verify.Users.AnyAsync(u => u.Id == userId));
        Assert.False(await verify.Sessions.AnyAsync(s => s.UserId == userId));

        // Public data remains, no longer tied to the person.
        Assert.Null((await verify.PriceEntries.SingleAsync(p => p.Id == priceId)).SubmittedByUserId);
        Assert.Null((await verify.Products.SingleAsync(p => p.Id == productId)).CreatedByUserId);
        Assert.Null((await verify.Reports.SingleAsync(r => r.Id == reportId)).ReporterUserId);

        // Tokens stop working.
        Assert.Equal(HttpStatusCode.Unauthorized, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, auth.Token)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Send(HttpMethod.Get, "/api/v1/auth/me", null, second.Token)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Login(Email, Password)).StatusCode);
    }

    [Fact]
    public async Task Delete_leaves_a_marker_and_audit_entry_without_personal_data()
    {
        var auth = await ReadAuth(await Register(Email));

        await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = Password }, auth.Token);

        await using var db = _database.CreateContext();
        var marker = await db.DeletionMarkers.SingleAsync();
        Assert.Equal(nameof(User), marker.EntityType);
        Assert.Equal(auth.User.Id, marker.EntityId);

        var audits = await db.AuditEntries.ToListAsync();
        Assert.Contains(audits, a => a.Action == AuditActions.AccountDeleted && a.ActorUserId is null);
        Assert.All(audits, a => Assert.Null(a.ActorUserId));
        var everything = string.Join("|", audits.Select(a => $"{a.Action}{a.EntityType}{a.DetailsJson}"))
            + marker.EntityType;
        Assert.DoesNotContain("jonas", everything);
        Assert.DoesNotContain(Password, everything);
        Assert.DoesNotContain(auth.Token, everything);
    }

    [Fact]
    public async Task Email_can_be_registered_again_after_deletion()
    {
        var auth = await ReadAuth(await Register(Email));
        await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = Password }, auth.Token);

        var again = await Register(Email);

        Assert.Equal(HttpStatusCode.Created, again.StatusCode);
    }

    [Fact]
    public async Task Wrong_password_on_delete_counts_toward_the_lock_out()
    {
        var auth = await ReadAuth(await Register(Email));

        for (var i = 0; i < 5; i++)
        {
            await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = "not my password!" }, auth.Token);
        }

        var response = await Send(HttpMethod.Delete, "/api/v1/auth/account", new { password = Password }, auth.Token);
        Assert.Equal(HttpStatusCode.TooManyRequests, response.StatusCode);
    }

    // ---------- price history stays append-only ----------

    [Fact]
    public async Task Price_submitter_can_be_cleared_but_not_reassigned()
    {
        await using var db = _database.CreateContext();
        await new DataSeeder(db).SeedAsync();

        var reassign = await Assert.ThrowsAsync<SqliteException>(() =>
            db.Database.ExecuteSqlRawAsync("""UPDATE "PriceEntries" SET "SubmittedByUserId" = 999999"""));
        Assert.Contains("submitter", reassign.Message);

        await db.Database.ExecuteSqlRawAsync("""UPDATE "PriceEntries" SET "SubmittedByUserId" = NULL""");
        Assert.False(await db.PriceEntries.AnyAsync(p => p.SubmittedByUserId != null));
    }

    // ---------- helpers ----------

    private Task<HttpResponseMessage> Register(string email, string password = Password) =>
        Send(HttpMethod.Post, "/api/v1/auth/register", new { email, password });

    private Task<HttpResponseMessage> Login(string email, string password) =>
        Send(HttpMethod.Post, "/api/v1/auth/login", new { email, password });

    private Task<HttpResponseMessage> Send(HttpMethod method, string path, object? body = null, string? token = null)
    {
        var request = new HttpRequestMessage(method, path);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        return _client.SendAsync(request);
    }

    private static async Task<AuthResponse> ReadAuth(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<AuthResponse>(Json))!;

    private static async Task<ErrorDto> ReadError(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<ErrorDto>(Json))!;
}
