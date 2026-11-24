using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Domain;
using Alusekis.Api.Prices;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class PriceSubmissionTests : IDisposable
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
    private long? _cityId;
    private int _users;

    public PriceSubmissionTests()
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
    public async Task A_new_price_is_a_new_entry_the_old_one_is_untouched_and_it_is_audited()
    {
        var (store, product) = await StoreAndProductAsync();
        var oldId = await AddPriceAsync(store, product, 150, Now.AddDays(-3));
        var (token, userId) = await SignInAsync();

        var response = await SubmitAsync(token, new { productId = product, storeId = store, priceCents = 160, idempotencyKey = "k-1" });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<SubmittedPriceDto>(Json))!;
        Assert.Equal(160, body.PriceCents);
        Assert.Equal(product, body.ProductId);
        Assert.Equal(store, body.StoreId);
        Assert.Equal(Now, body.ObservedAt); // server time, not anything from the client
        Assert.Equal(DateTimeKind.Utc, body.ObservedAt.Kind);
        Assert.False(body.IsLargeChange);

        await using var db = _database.CreateContext();
        var entries = await db.PriceEntries.AsNoTracking().OrderBy(p => p.Id).ToListAsync();
        Assert.Equal(2, entries.Count);
        var old = entries[0];
        Assert.Equal(oldId, old.Id);
        Assert.Equal(150, old.PriceCents); // history kept as it was
        Assert.Equal(Now.AddDays(-3), old.ObservedAt);
        var created = entries[1];
        Assert.Equal(body.Id, created.Id);
        Assert.Equal(userId, created.SubmittedByUserId);
        Assert.Equal(PriceStatus.Approved, created.Status);
        Assert.Equal(Now, created.ObservedAt);
        Assert.Equal(Now, created.CreatedAt);

        var audit = await db.AuditEntries.AsNoTracking().SingleAsync(a => a.Action == "PriceSubmitted");
        Assert.Equal(nameof(PriceEntry), audit.EntityType);
        Assert.Equal(created.Id, audit.EntityId);
        Assert.Equal(userId, audit.ActorUserId);
        Assert.Equal(Now, audit.CreatedAt);
        Assert.DoesNotContain("k-1", audit.DetailsJson); // no idempotency key
        Assert.DoesNotContain(token, audit.DetailsJson ?? "");
        Assert.DoesNotContain(Password, audit.DetailsJson ?? "");
    }

    [Fact]
    public async Task The_first_price_of_a_pair_has_nothing_to_compare_with()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, 49_999, "first"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.False((await response.Content.ReadFromJsonAsync<SubmittedPriceDto>(Json))!.IsLargeChange);
    }

    // ---------- who may submit ----------

    [Fact]
    public async Task Without_signing_in_the_request_is_401_and_nothing_is_written()
    {
        var (store, product) = await StoreAndProductAsync();

        var response = await SubmitAsync(token: null, Body(product, store, 150, "anon"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(ErrorCodes.Unauthorized, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Fact]
    public async Task A_guest_is_403_and_nothing_is_written()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync(Role.Guest);

        var response = await SubmitAsync(token, Body(product, store, 150, "guest"));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(ErrorCodes.Forbidden, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(Role.User)]
    [InlineData(Role.Admin)]
    public async Task A_user_and_an_admin_may_submit(Role role)
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync(role);

        var response = await SubmitAsync(token, Body(product, store, 150, "ok"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // ---------- input ----------

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-150)]
    [InlineData(50_001)]
    public async Task A_price_outside_1_to_50000_cents_is_rejected_without_writing(int cents)
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, cents, "bad-price"));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.PriceInvalid, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(1)]
    [InlineData(50_000)]
    public async Task The_price_limits_themselves_are_accepted(int cents)
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, cents, "edge"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task A_missing_price_is_rejected()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, new { productId = product, storeId = store, idempotencyKey = "no-price" });

        Assert.Equal(ErrorCodes.PriceInvalid, (await ReadErrorAsync(response)).Code);
    }

    [Fact]
    public async Task An_unknown_product_or_store_is_404_without_writing()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var noProduct = await SubmitAsync(token, Body(999_999, store, 150, "p"));
        var noStore = await SubmitAsync(token, Body(product, 999_999, 150, "s"));

        Assert.Equal(HttpStatusCode.NotFound, noProduct.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, noStore.StatusCode);
        Assert.Equal(ErrorCodes.NotFound, (await ReadErrorAsync(noProduct)).Code);
        Assert.Equal(ErrorCodes.NotFound, (await ReadErrorAsync(noStore)).Code);
        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_idempotency_key_is_required(string? key)
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, new { productId = product, storeId = store, priceCents = 150, idempotencyKey = key });

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Fact]
    public async Task An_idempotency_key_over_100_characters_is_rejected()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, 150, new string('k', 101)));

        Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
    }

    // ---------- idempotency ----------

    [Fact]
    public async Task The_same_key_with_the_same_content_returns_the_stored_result_and_creates_one_entry()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        var first = await SubmitAsync(token, Body(product, store, 150, "same"));
        _clock.Advance(TimeSpan.FromMinutes(5)); // a later retry must still get the original answer
        var second = await SubmitAsync(token, Body(product, store, 150, "same"));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal(await first.Content.ReadAsStringAsync(), await second.Content.ReadAsStringAsync());
        Assert.Equal("true", second.Headers.GetValues(PriceEndpoints.ReplayHeader).Single());
        Assert.Equal((1, 1, 1), await CountsAsync()); // one entry, one audit, one stored result
    }

    [Fact]
    public async Task The_same_key_with_different_content_is_rejected()
    {
        var (store, product) = await StoreAndProductAsync();
        var (token, _) = await SignInAsync();

        await SubmitAsync(token, Body(product, store, 150, "reused"));
        var other = await SubmitAsync(token, Body(product, store, 155, "reused"));

        Assert.Equal(HttpStatusCode.Conflict, other.StatusCode);
        Assert.Equal(ErrorCodes.IdempotencyKeyReused, (await ReadErrorAsync(other)).Code);
        Assert.Equal((1, 1, 1), await CountsAsync());
    }

    [Fact]
    public async Task Keys_belong_to_a_user_so_two_users_may_use_the_same_one()
    {
        var (store, product) = await StoreAndProductAsync();
        var (a, _) = await SignInAsync();
        var (b, _) = await SignInAsync();

        var first = await SubmitAsync(a, Body(product, store, 150, "shared"));
        var second = await SubmitAsync(b, Body(product, store, 150, "shared"));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal((2, 2, 2), await CountsAsync());
    }

    // ---------- large change (FR-08) ----------

    [Theory]
    [InlineData(15_000)] // +50 %: allowed
    [InlineData(5_000)] // -50 %: allowed
    public async Task Exactly_50_percent_is_allowed_without_confirmation(int newCents)
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 10_000, Now.AddDays(-1));
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, newCents, "fifty"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.False((await response.Content.ReadFromJsonAsync<SubmittedPriceDto>(Json))!.IsLargeChange);
    }

    [Theory]
    [InlineData(15_001)] // +50.01 %
    [InlineData(4_999)] // -50.01 %
    public async Task More_than_50_percent_needs_confirmation_and_tells_the_previous_price(int newCents)
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 10_000, Now.AddDays(-1));
        var (token, _) = await SignInAsync();

        var response = await SubmitAsync(token, Body(product, store, newCents, "large"));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<LargePriceChangeDto>(Json))!;
        Assert.Equal(ErrorCodes.LargePriceChange, body.Code);
        Assert.Equal(10_000, body.PreviousPriceCents);
        Assert.False(string.IsNullOrEmpty(body.RequestId));
        Assert.Equal((1, 0, 0), await CountsAsync()); // only the old entry; the failure is not stored
    }

    [Fact]
    public async Task A_confirmed_large_change_is_saved_and_marked_and_the_key_can_be_reused_after_the_refusal()
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 100, Now.AddDays(-1));
        var (token, _) = await SignInAsync();

        var refused = await SubmitAsync(token, Body(product, store, 300, "confirm-me"));
        var confirmed = await SubmitAsync(token, Body(product, store, 300, "confirm-me", confirm: true));

        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal(HttpStatusCode.Created, confirmed.StatusCode);
        var body = (await confirmed.Content.ReadFromJsonAsync<SubmittedPriceDto>(Json))!;
        Assert.True(body.IsLargeChange);
        await using var db = _database.CreateContext();
        Assert.True((await db.PriceEntries.AsNoTracking().SingleAsync(p => p.Id == body.Id)).IsLargeChange);
    }

    [Fact]
    public async Task The_previous_price_is_the_newest_valid_one_not_a_rejected_entry()
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 100, Now.AddDays(-3));
        await AddPriceAsync(store, product, 1_000, Now.AddDays(-1), PriceStatus.Rejected); // wrong: ignored

        var (token, _) = await SignInAsync();
        var response = await SubmitAsync(token, Body(product, store, 140, "vs-valid"));

        // 140 vs 100 is +40 %: fine. Against the rejected 1000 it would have been -86 %.
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Theory]
    [InlineData(10_000, 15_000, false)]
    [InlineData(10_000, 15_001, true)]
    [InlineData(10_000, 5_000, false)]
    [InlineData(10_000, 4_999, true)]
    [InlineData(3, 4, false)] // +33 %
    [InlineData(2, 3, false)] // +50 %
    [InlineData(2, 4, true)] // +100 %
    [InlineData(1, 50_000, true)]
    [InlineData(50_000, 1, true)]
    [InlineData(150, 150, false)]
    public void The_large_change_rule_uses_whole_numbers(int previous, int next, bool large)
    {
        Assert.Equal(large, PriceRules.IsLargeChange(previous, next));
    }

    // ---------- one transaction ----------

    [Theory]
    [InlineData("AuditEntries")] // fails after the price entry was written
    [InlineData("RequestResults")] // fails after the price entry and the audit were written
    public async Task A_failure_after_the_price_entry_rolls_everything_back(string failingTable)
    {
        var (store, product) = await StoreAndProductAsync();
        var oldId = await AddPriceAsync(store, product, 150, Now.AddDays(-2));
        var (token, _) = await SignInAsync();
        await using (var db = _database.CreateContext())
        {
            await db.Database.ExecuteSqlRawAsync(
                $"CREATE TRIGGER \"TR_Test_Fail\" BEFORE INSERT ON \"{failingTable}\" " +
                "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END;");
        }

        var response = await SubmitAsync(token, Body(product, store, 160, "boom"));

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal(ErrorCodes.InternalError, (await ReadErrorAsync(response)).Code);
        await using var verify = _database.CreateContext();
        Assert.Equal([oldId], await verify.PriceEntries.Select(p => p.Id).ToListAsync()); // no new entry
        Assert.Equal(0, await verify.AuditEntries.CountAsync(a => a.Action == "PriceSubmitted"));
        Assert.Equal(0, await verify.RequestResults.CountAsync());
    }

    [Fact]
    public async Task The_price_service_refuses_to_run_outside_a_transaction()
    {
        var (store, product) = await StoreAndProductAsync();
        var (_, userId) = await SignInAsync();
        await using var db = _database.CreateContext();
        var service = new PriceService(db, _clock);

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            service.CreatePriceEntryAsync(new CreatePriceCommand(userId, product, store, 150, false), CancellationToken.None));

        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    [Fact]
    public async Task The_price_service_does_not_commit_on_its_own()
    {
        var (store, product) = await StoreAndProductAsync();
        var (_, userId) = await SignInAsync();

        await using (var db = _database.CreateContext())
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            var result = await new PriceService(db, _clock)
                .CreatePriceEntryAsync(new CreatePriceCommand(userId, product, store, 150, false), CancellationToken.None);
            Assert.Equal(PriceCreationStatus.Created, result.Status);
            // The caller decides: here it does not commit.
        }

        Assert.Equal((0, 0, 0), await CountsAsync());
    }

    // ---------- helpers ----------

    private static object Body(long productId, long storeId, int cents, string key, bool confirm = false) =>
        new { productId, storeId, priceCents = cents, idempotencyKey = key, confirmLargeChange = confirm };

    private Task<HttpResponseMessage> SubmitAsync(string? token, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/prices") { Content = JsonContent.Create(body) };
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

    private static async Task<ErrorDto> ReadErrorAsync(HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<ErrorDto>(Json))!;

    /// <summary>Price entries, "PriceSubmitted" audit entries and stored request results.</summary>
    private async Task<(int Prices, int Audits, int Results)> CountsAsync()
    {
        await using var db = _database.CreateContext();
        return (
            await db.PriceEntries.CountAsync(),
            await db.AuditEntries.CountAsync(a => a.Action == "PriceSubmitted"),
            await db.RequestResults.CountAsync());
    }

    private async Task<(long Store, long Product)> StoreAndProductAsync()
    {
        await using var db = _database.CreateContext();
        if (_cityId is null)
        {
            var city = new City { Name = "Vilnius", NormalizedName = "vilnius" };
            db.Cities.Add(city);
            await db.SaveChangesAsync();
            _cityId = city.Id;
        }

        var store = new Store { CityId = _cityId.Value, Name = "Maxima XX", Address = "Ukmergės g. 282", CreatedAt = Now };
        var product = new Product { Name = "Alus", NormalizedName = "alus", VolumeMl = 500, CreatedAt = Now };
        db.AddRange(store, product);
        await db.SaveChangesAsync();
        return (store.Id, product.Id);
    }

    private async Task<long> AddPriceAsync(
        long storeId, long productId, int cents, DateTime observedAt, PriceStatus status = PriceStatus.Approved)
    {
        await using var db = _database.CreateContext();
        var price = new PriceEntry
        {
            StoreId = storeId,
            ProductId = productId,
            PriceCents = cents,
            Status = status,
            ObservedAt = observedAt,
            CreatedAt = observedAt,
        };
        db.PriceEntries.Add(price);
        await db.SaveChangesAsync();
        return price.Id;
    }
}
