using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Domain;
using Alusekis.Api.Prices;
using Alusekis.Api.Reports;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class ReportTests : IDisposable
{
    private const string Password = "correct horse battery";

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;
    private int _users;

    public ReportTests()
    {
        _factory = new AuthApiFactory(_database.ConnectionString, _clock, new CapturingEmailSender());
        _client = _factory.CreateClient();
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        _database.Dispose();
    }

    private DateTime Now => _clock.GetUtcNow().UtcDateTime;

    // ---------- success ----------

    [Fact]
    public async Task A_report_is_stored_as_new_and_the_price_entry_is_not_changed()
    {
        var price = await PriceEntryAsync(150);
        var (token, userId) = await SignInAsync();
        var before = await SnapshotAsync(price);

        var response = await ReportAsync(token, Body(price, "WrongPrice", "Kaina kita lentynoje", "r-1"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<SubmittedReportDto>(Json))!;
        Assert.Equal(ReportStatus.New, body.Status);
        Assert.Equal(Now, body.SubmittedAt); // server time
        Assert.Equal(DateTimeKind.Utc, body.SubmittedAt.Kind);

        await using var db = _database.CreateContext();
        var report = await db.Reports.AsNoTracking().SingleAsync();
        Assert.Equal(body.ReportId, report.Id);
        Assert.Equal(price, report.PriceEntryId);
        Assert.Equal(userId, report.ReporterUserId);
        Assert.Equal(ReportReason.WrongPrice, report.Reason);
        Assert.Equal("Kaina kita lentynoje", report.Comment);
        Assert.Equal(ReportStatus.New, report.Status);
        Assert.Equal(Now, report.SubmittedAt);
        Assert.Null(report.ResolvedAt);
        Assert.Null(report.ResolvedByUserId);

        // The price is exactly as it was: not changed, not hidden.
        Assert.Equal(before, await SnapshotAsync(price));
        Assert.Equal(1, await db.PriceEntries.CountAsync());
    }

    [Theory]
    [InlineData("WrongPrice", ReportReason.WrongPrice, null)]
    [InlineData("DifferentProduct", ReportReason.DifferentProduct, null)]
    [InlineData("OutdatedData", ReportReason.OutdatedData, null)]
    [InlineData("Other", ReportReason.Other, "Kita problema")]
    public async Task Every_reason_is_accepted(string reason, ReportReason expected, string? comment)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, reason, comment, "reason"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        await using var db = _database.CreateContext();
        Assert.Equal(expected, (await db.Reports.AsNoTracking().SingleAsync()).Reason);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("    ")]
    public async Task A_missing_or_blank_comment_is_stored_as_nothing_for_the_other_reasons(string? comment)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "WrongPrice", comment, "blank"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        await using var db = _database.CreateContext();
        Assert.Null((await db.Reports.AsNoTracking().SingleAsync()).Comment);
    }

    [Fact]
    public async Task The_comment_is_trimmed()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        await ReportAsync(token, Body(price, "Other", "   per brangu   ", "trim"));

        await using var db = _database.CreateContext();
        Assert.Equal("per brangu", (await db.Reports.AsNoTracking().SingleAsync()).Comment);
    }

    [Theory]
    [InlineData(Role.User)]
    [InlineData(Role.Admin)]
    public async Task A_user_and_an_admin_may_report(Role role)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync(role);

        var response = await ReportAsync(token, Body(price, "WrongPrice", null, "ok"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // ---------- who may report ----------

    [Fact]
    public async Task Without_signing_in_the_request_is_401_and_nothing_is_written()
    {
        var price = await PriceEntryAsync(150);

        var response = await ReportAsync(token: null, Body(price, "WrongPrice", null, "anon"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(ErrorCodes.Unauthorized, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0), await CountsAsync());
    }

    [Fact]
    public async Task A_guest_is_403_and_nothing_is_written()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync(Role.Guest);

        var response = await ReportAsync(token, Body(price, "WrongPrice", null, "guest"));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(ErrorCodes.Forbidden, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0), await CountsAsync());
    }

    // ---------- input ----------

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Nonsense")]
    [InlineData("wrong price")]
    [InlineData("4")]
    [InlineData("3")] // a number is not a reason, even when it is a valid enum value
    [InlineData("-1")]
    public async Task A_missing_or_wrong_reason_is_rejected_without_writing(string? reason)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, reason, "komentaras", "bad-reason"));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("      ")]
    public async Task The_reason_Other_needs_a_comment(string? comment)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "Other", comment, "other"));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0), await CountsAsync());
    }

    [Fact]
    public async Task The_reason_Other_with_a_comment_is_accepted()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "Other", "Prekė nebeparduodama", "other-ok"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Theory]
    [InlineData(500, true)]
    [InlineData(501, false)]
    public async Task The_comment_may_have_500_characters_but_not_501(int length, bool accepted)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "WrongPrice", new string('ž', length), "len"));

        Assert.Equal(accepted ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(accepted ? (1, 1) : (0, 0), await CountsAsync());
    }

    [Fact]
    public async Task The_length_limit_applies_after_trimming()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "WrongPrice", "  " + new string('a', 500) + "  ", "trim-len"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task An_unknown_price_entry_is_404_and_nothing_is_created()
    {
        await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(999_999, "WrongPrice", null, "no-entry"));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(ErrorCodes.NotFound, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0), await CountsAsync());
    }

    [Fact]
    public async Task A_missing_price_entry_id_is_rejected()
    {
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, new { reason = "WrongPrice", idempotencyKey = "no-id" });

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal((0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_idempotency_key_is_required(string? key)
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var response = await ReportAsync(token, Body(price, "WrongPrice", null, key));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal((0, 0), await CountsAsync());
    }

    // ---------- idempotency ----------

    [Fact]
    public async Task The_same_key_with_the_same_content_returns_the_stored_result_and_creates_one_report()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        var first = await ReportAsync(token, Body(price, "WrongPrice", "tas pats", "same"));
        _clock.Advance(TimeSpan.FromMinutes(5));
        var second = await ReportAsync(token, Body(price, "WrongPrice", "tas pats", "same"));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal(await first.Content.ReadAsStringAsync(), await second.Content.ReadAsStringAsync());
        Assert.Equal("true", second.Headers.GetValues(PriceEndpoints.ReplayHeader).Single());
        Assert.Equal((1, 1), await CountsAsync());
    }

    [Fact]
    public async Task The_same_key_with_different_content_is_rejected()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();

        await ReportAsync(token, Body(price, "WrongPrice", null, "reused"));
        var other = await ReportAsync(token, Body(price, "OutdatedData", null, "reused"));

        Assert.Equal(HttpStatusCode.Conflict, other.StatusCode);
        Assert.Equal(ErrorCodes.IdempotencyKeyReused, (await ReadErrorAsync(other)).Code);
        Assert.Equal((1, 1), await CountsAsync());
    }

    // ---------- privacy ----------

    [Fact]
    public async Task The_answer_has_no_reporter_e_mail_and_nothing_but_the_three_fields()
    {
        var price = await PriceEntryAsync(150);
        var (token, userId) = await SignInAsync();
        var email = await EmailOfAsync(userId);

        var response = await ReportAsync(token, Body(price, "WrongPrice", null, "privacy"));

        var text = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain(email, text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("@", text);
        using var document = JsonDocument.Parse(text);
        var names = document.RootElement.EnumerateObject().Select(p => p.Name).Order().ToArray();
        Assert.Equal(["reportId", "status", "submittedAt"], names);
    }

    [Fact]
    public async Task An_error_answer_does_not_leak_the_e_mail_either()
    {
        var (token, userId) = await SignInAsync();
        var email = await EmailOfAsync(userId);

        var response = await ReportAsync(token, Body(999_999, "WrongPrice", null, "privacy-err"));

        Assert.DoesNotContain(email, await response.Content.ReadAsStringAsync(), StringComparison.OrdinalIgnoreCase);
    }

    // ---------- account deletion ----------

    [Fact]
    public async Task Deleting_the_account_keeps_the_report_and_only_detaches_the_reporter()
    {
        var price = await PriceEntryAsync(150);
        var (token, userId) = await SignInAsync();
        await ReportAsync(token, Body(price, "WrongPrice", "paliks", "del"));

        var delete = new HttpRequestMessage(HttpMethod.Delete, "/api/v1/auth/account")
        {
            Content = JsonContent.Create(new { password = Password }),
        };
        delete.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var deleted = await _client.SendAsync(delete);

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        await using var db = _database.CreateContext();
        Assert.False(await db.Users.AnyAsync(u => u.Id == userId));
        var report = await db.Reports.AsNoTracking().SingleAsync();
        Assert.Null(report.ReporterUserId);
        Assert.Equal("paliks", report.Comment);
        Assert.Equal(ReportStatus.New, report.Status);
        Assert.Equal(price, report.PriceEntryId);
    }

    // ---------- one transaction ----------

    [Fact]
    public async Task A_failure_while_storing_the_result_leaves_no_report()
    {
        var price = await PriceEntryAsync(150);
        var (token, _) = await SignInAsync();
        await using (var db = _database.CreateContext())
        {
            await db.Database.ExecuteSqlRawAsync(
                "CREATE TRIGGER \"TR_Test_Fail\" BEFORE INSERT ON \"RequestResults\" " +
                "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END;");
        }

        var response = await ReportAsync(token, Body(price, "WrongPrice", null, "boom"));

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal((0, 0), await CountsAsync());
    }

    // ---------- helpers ----------

    private static object Body(long priceEntryId, string? reason, string? comment, string? key) =>
        new { priceEntryId, reason, comment, idempotencyKey = key };

    private Task<HttpResponseMessage> ReportAsync(string? token, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/reports") { Content = JsonContent.Create(body) };
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        return _client.SendAsync(request);
    }

    /// <summary>Registers a fresh account and returns its token; the role is set in the database.</summary>
    private async Task<(string Token, long UserId)> SignInAsync(Role role = Role.User)
    {
        var email = $"user{++_users}@example.lt";
        var response = await _client.PostAsJsonAsync("/api/v1/auth/register", new { email, password = Password });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var auth = (await response.Content.ReadFromJsonAsync<AuthResponse>(Json))!;

        if (role != Role.User)
        {
            await using var db = _database.CreateContext();
            var user = await db.Users.SingleAsync(u => u.Id == auth.User.Id);
            user.Role = role;
            await db.SaveChangesAsync();
        }

        return (auth.Token, auth.User.Id);
    }

    private async Task<string> EmailOfAsync(long userId)
    {
        await using var db = _database.CreateContext();
        return (await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId)).Email;
    }

    private static async Task<ErrorDto> ReadErrorAsync(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<ErrorDto>(Json))!;

    /// <summary>Reports and stored request results.</summary>
    private async Task<(int Reports, int Results)> CountsAsync()
    {
        await using var db = _database.CreateContext();
        return (await db.Reports.CountAsync(), await db.RequestResults.CountAsync());
    }

    /// <summary>Everything about a price entry, to prove that a report leaves it alone.</summary>
    private async Task<string> SnapshotAsync(long priceEntryId)
    {
        await using var db = _database.CreateContext();
        var p = await db.PriceEntries.AsNoTracking().SingleAsync(x => x.Id == priceEntryId);
        return $"{p.ProductId}|{p.StoreId}|{p.SubmittedByUserId}|{p.PriceCents}|{p.Status}|{p.ObservedAt:O}|{p.CreatedAt:O}|{p.IsLargeChange}";
    }

    private async Task<long> PriceEntryAsync(int cents)
    {
        await using var db = _database.CreateContext();
        var city = new City { Name = "Vilnius", NormalizedName = "vilnius" };
        db.Cities.Add(city);
        await db.SaveChangesAsync();
        var store = new Store { CityId = city.Id, Name = "Maxima XX", Address = "Ukmergės g. 282", CreatedAt = Now };
        var product = new Product { Name = "Alus", NormalizedName = "alus", VolumeMl = 500, CreatedAt = Now };
        db.AddRange(store, product);
        await db.SaveChangesAsync();
        var price = new PriceEntry
        {
            StoreId = store.Id,
            ProductId = product.Id,
            PriceCents = cents,
            Status = PriceStatus.Approved,
            ObservedAt = Now.AddDays(-1),
            CreatedAt = Now.AddDays(-1),
        };
        db.PriceEntries.Add(price);
        await db.SaveChangesAsync();
        return price.Id;
    }
}
