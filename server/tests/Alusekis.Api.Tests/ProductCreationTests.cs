using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Alusekis.Api.Api;
using Alusekis.Api.Auth;
using Alusekis.Api.Domain;
using Alusekis.Api.Prices;
using Alusekis.Api.Products;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class ProductCreationTests : IDisposable
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

    public ProductCreationTests()
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
    public async Task A_new_product_gets_its_first_price_and_an_audit_entry()
    {
        var store = await StoreAsync();
        var (token, userId) = await SignInAsync();

        var response = await CreateAsync(token, Body("  Žalgiris Šviesus ", 500, store, 119, "k-1"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<CreateProductResponse>(Json))!;
        Assert.Equal("Žalgiris Šviesus", body.Product.Name); // trimmed
        Assert.Equal(500, body.Product.VolumeMl);
        Assert.Equal(body.Product.Id, body.Price.ProductId);
        Assert.Equal(store, body.Price.StoreId);
        Assert.Equal(119, body.Price.PriceCents);
        Assert.Equal(Now, body.Price.ObservedAt);
        Assert.False(body.Price.IsLargeChange);

        await using var db = _database.CreateContext();
        var product = await db.Products.AsNoTracking().SingleAsync();
        Assert.Equal(body.Product.Id, product.Id);
        Assert.Equal(TextNormalizer.NormalizeName("Žalgiris Šviesus"), product.NormalizedName);
        Assert.Equal(userId, product.CreatedByUserId);
        Assert.Equal(Now, product.CreatedAt);

        var price = await db.PriceEntries.AsNoTracking().SingleAsync();
        Assert.Equal(body.Price.Id, price.Id);
        Assert.Equal(product.Id, price.ProductId);
        Assert.Equal(userId, price.SubmittedByUserId);
        Assert.Equal(PriceStatus.Approved, price.Status);

        var audit = await db.AuditEntries.AsNoTracking().SingleAsync(a => a.Action == "ProductCreated");
        Assert.Equal(nameof(Product), audit.EntityType);
        Assert.Equal(product.Id, audit.EntityId);
        Assert.Equal(userId, audit.ActorUserId);
        Assert.Equal(Now, audit.CreatedAt);
        Assert.DoesNotContain("k-1", audit.DetailsJson);
        Assert.DoesNotContain(token, audit.DetailsJson ?? "");
        Assert.DoesNotContain(Password, audit.DetailsJson ?? "");

        Assert.Equal(1, await db.RequestResults.CountAsync());
    }

    [Fact]
    public async Task The_new_product_is_found_by_the_search()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();
        await CreateAsync(token, Body("Žalgiris", 500, store, 119, "k-search"));

        var search = await _client.GetAsync("/api/v1/products/search?q=zalgiris");

        Assert.Equal(HttpStatusCode.OK, search.StatusCode);
        Assert.Contains("Žalgiris", await search.Content.ReadAsStringAsync());
    }

    // ---------- who may create ----------

    [Fact]
    public async Task Without_signing_in_the_request_is_401_and_nothing_is_written()
    {
        var store = await StoreAsync();

        var response = await CreateAsync(token: null, Body("Alus", 500, store, 100, "anon"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    [Fact]
    public async Task A_guest_is_403_and_nothing_is_written()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync(Role.Guest);

        var response = await CreateAsync(token, Body("Alus", 500, store, 100, "guest"));

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal(ErrorCodes.Forbidden, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(Role.User)]
    [InlineData(Role.Admin)]
    public async Task A_user_and_an_admin_may_create(Role role)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync(role);

        var response = await CreateAsync(token, Body("Alus", 500, store, 100, "ok"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // ---------- duplicates ----------

    [Fact]
    public async Task The_same_name_and_volume_with_other_case_and_spaces_is_a_duplicate_and_creates_nothing()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();
        var first = await CreateAsync(token, Body("žalgiris", 500, store, 119, "d-1"));
        var firstBody = (await first.Content.ReadFromJsonAsync<CreateProductResponse>(Json))!;

        var response = await CreateAsync(token, Body("  ŽALGIRIS ", 500, store, 129, "d-2"));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<ProductExistsDto>(Json))!;
        Assert.Equal(ErrorCodes.ProductExists, body.Code);
        Assert.Equal(firstBody.Product.Id, body.ExistingProduct.Id);
        Assert.Equal("žalgiris", body.ExistingProduct.Name);
        Assert.Equal(500, body.ExistingProduct.VolumeMl);
        Assert.False(string.IsNullOrEmpty(body.RequestId));
        Assert.Equal((1, 1, 1, 1), await CountsAsync()); // only the first one exists
    }

    [Fact]
    public async Task The_same_name_with_another_volume_is_a_different_product()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();
        await CreateAsync(token, Body("Žalgiris", 500, store, 119, "v-1"));

        var response = await CreateAsync(token, Body("Žalgiris", 330, store, 99, "v-2"));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal((2, 2, 2, 2), await CountsAsync());
    }

    [Fact]
    public async Task Parallel_requests_for_the_same_product_give_one_product_and_product_exists_never_a_500()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var responses = await Task.WhenAll(Enumerable.Range(0, 6).Select(i =>
            CreateAsync(token, Body("Lenktynės", 500, store, 100 + i, $"race-{i}"))));

        var statuses = responses.Select(r => r.StatusCode).ToList();
        Assert.DoesNotContain(HttpStatusCode.InternalServerError, statuses);
        Assert.Equal(1, statuses.Count(s => s == HttpStatusCode.Created));
        foreach (var loser in responses.Where(r => r.StatusCode != HttpStatusCode.Created))
        {
            Assert.Equal(HttpStatusCode.Conflict, loser.StatusCode);
            Assert.Equal(ErrorCodes.ProductExists, (await loser.Content.ReadFromJsonAsync<ProductExistsDto>(Json))!.Code);
        }

        await using var db = _database.CreateContext();
        Assert.Equal(1, await db.Products.CountAsync());
        Assert.Equal(1, await db.PriceEntries.CountAsync());
    }

    // ---------- input ----------

    [Theory]
    [InlineData(1, false)]
    [InlineData(2, true)]
    [InlineData(150, true)]
    [InlineData(151, false)]
    public async Task The_name_must_be_2_to_150_characters(int length, bool accepted)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, Body(new string('a', length), 500, store, 100, "name"));

        Assert.Equal(accepted ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity, response.StatusCode);
        if (!accepted)
        {
            Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
            Assert.Equal((0, 0, 0, 0), await CountsAsync());
        }
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("      ")]
    [InlineData(" a ")] // 1 character once trimmed
    public async Task A_missing_or_blank_name_is_rejected(string? name)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, new { name, volumeMl = 500, storeId = store, priceCents = 100, idempotencyKey = "blank" });

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(50_000, true)]
    [InlineData(50_001, false)]
    [InlineData(-5, false)]
    public async Task The_volume_must_be_1_to_50000_ml(int volume, bool accepted)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, Body("Alus", volume, store, 100, "vol"));

        Assert.Equal(accepted ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity, response.StatusCode);
        if (!accepted)
        {
            Assert.Equal(ErrorCodes.ValidationFailed, (await ReadErrorAsync(response)).Code);
            Assert.Equal((0, 0, 0, 0), await CountsAsync());
        }
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(50_000, true)]
    [InlineData(50_001, false)]
    public async Task The_price_must_be_1_to_50000_cents(int cents, bool accepted)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, Body("Alus", 500, store, cents, "price"));

        Assert.Equal(accepted ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity, response.StatusCode);
        if (!accepted)
        {
            Assert.Equal(ErrorCodes.PriceInvalid, (await ReadErrorAsync(response)).Code);
            Assert.Equal((0, 0, 0, 0), await CountsAsync());
        }
    }

    [Fact]
    public async Task A_missing_volume_price_or_store_is_rejected()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var noVolume = await CreateAsync(token, new { name = "Alus", storeId = store, priceCents = 100, idempotencyKey = "a" });
        var noPrice = await CreateAsync(token, new { name = "Alus", volumeMl = 500, storeId = store, idempotencyKey = "b" });
        var noStore = await CreateAsync(token, new { name = "Alus", volumeMl = 500, priceCents = 100, idempotencyKey = "c" });

        Assert.All([noVolume, noPrice, noStore], r => Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode));
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public async Task The_idempotency_key_is_required(string? key)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, Body("Alus", 500, store, 100, key!));

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    [Fact]
    public async Task An_unknown_store_is_404_without_writing()
    {
        var (token, _) = await SignInAsync();

        var response = await CreateAsync(token, Body("Alus", 500, 999_999, 100, "no-store"));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(ErrorCodes.NotFound, (await ReadErrorAsync(response)).Code);
        Assert.Equal((0, 0, 0, 0), await CountsAsync());
    }

    // ---------- idempotency ----------

    [Fact]
    public async Task The_same_key_with_the_same_content_returns_the_stored_result_and_creates_one_product()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        var first = await CreateAsync(token, Body("Alus", 500, store, 150, "same"));
        _clock.Advance(TimeSpan.FromMinutes(5));
        var second = await CreateAsync(token, Body("  ALUS ", 500, store, 150, "same"));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        Assert.Equal(await first.Content.ReadAsStringAsync(), await second.Content.ReadAsStringAsync());
        Assert.Equal("true", second.Headers.GetValues(PriceEndpoints.ReplayHeader).Single());
        Assert.Equal((1, 1, 1, 1), await CountsAsync());
    }

    [Fact]
    public async Task The_same_key_with_different_content_is_rejected()
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();

        await CreateAsync(token, Body("Alus", 500, store, 150, "reused"));
        var other = await CreateAsync(token, Body("Alus", 500, store, 155, "reused"));

        Assert.Equal(HttpStatusCode.Conflict, other.StatusCode);
        Assert.Equal(ErrorCodes.IdempotencyKeyReused, (await ReadErrorAsync(other)).Code);
        Assert.Equal((1, 1, 1, 1), await CountsAsync());
    }

    // ---------- one transaction ----------

    [Theory]
    [InlineData("PriceEntries")] // fails right after the product was written
    [InlineData("AuditEntries")] // fails after the product and the price were written
    [InlineData("RequestResults")] // fails after product, price and audit were written
    public async Task A_failure_after_the_product_was_created_rolls_everything_back(string failingTable)
    {
        var store = await StoreAsync();
        var (token, _) = await SignInAsync();
        await using (var db = _database.CreateContext())
        {
            await db.Database.ExecuteSqlRawAsync(
                $"CREATE TRIGGER \"TR_Test_Fail\" BEFORE INSERT ON \"{failingTable}\" " +
                "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END;");
        }

        var response = await CreateAsync(token, Body("Alus", 500, store, 150, "boom"));

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal(ErrorCodes.InternalError, (await ReadErrorAsync(response)).Code);
        await using var verify = _database.CreateContext();
        Assert.Equal(0, await verify.Products.CountAsync());
        Assert.Equal(0, await verify.PriceEntries.CountAsync());
        Assert.Equal(0, await verify.AuditEntries.CountAsync(a => a.Action == "ProductCreated"));
        Assert.Equal(0, await verify.RequestResults.CountAsync());
    }

    // ---------- helpers ----------

    private static object Body(string name, int volumeMl, long storeId, int cents, string key) =>
        new { name, volumeMl, storeId, priceCents = cents, idempotencyKey = key };

    private Task<HttpResponseMessage> CreateAsync(string? token, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/v1/products") { Content = JsonContent.Create(body) };
        if (token is not null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }

        return _client.SendAsync(request);
    }

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

    /// <summary>Products, price entries, "ProductCreated" audit entries and stored request results.</summary>
    private async Task<(int Products, int Prices, int Audits, int Results)> CountsAsync()
    {
        await using var db = _database.CreateContext();
        return (
            await db.Products.CountAsync(),
            await db.PriceEntries.CountAsync(),
            await db.AuditEntries.CountAsync(a => a.Action == "ProductCreated"),
            await db.RequestResults.CountAsync());
    }

    private async Task<long> StoreAsync()
    {
        await using var db = _database.CreateContext();
        var city = new City { Name = "Vilnius", NormalizedName = "vilnius" };
        db.Cities.Add(city);
        await db.SaveChangesAsync();
        var store = new Store { CityId = city.Id, Name = "Maxima XX", Address = "Ukmergės g. 282", CreatedAt = Now };
        db.Stores.Add(store);
        await db.SaveChangesAsync();
        return store.Id;
    }
}
