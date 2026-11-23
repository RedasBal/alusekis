using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Stores;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Alusekis.Api.Tests;

public sealed class StorePricesTests : IDisposable
{
    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;
    private long? _cityId;

    public StorePricesTests()
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

    [Fact]
    public async Task Returns_the_stores_products_with_price_and_check_date()
    {
        var store = await AddStoreAsync("Maxima XX", "Ukmergės g. 282");
        var beer = await AddProductAsync("Švyturys Ekstra", 500);
        var observed = Now.AddDays(-2);
        var entry = await AddPriceAsync(store, beer, 149, observed);

        var body = await GetPricesAsync(store);

        Assert.Equal(new StoreSummaryDto(store, "Maxima XX", "Ukmergės g. 282"), body.Store);
        Assert.Equal(1, body.Total);
        Assert.Equal(1, body.Page);
        Assert.Equal(20, body.PageSize);
        var item = Assert.Single(body.Items);
        Assert.Equal(entry, item.PriceEntryId);
        Assert.Equal(beer, item.ProductId);
        Assert.Equal("Švyturys Ekstra", item.ProductName);
        Assert.Equal(500, item.VolumeMl);
        Assert.Equal(149, item.PriceCents);
        Assert.Equal(observed, item.ObservedAt);
        Assert.Equal(DateTimeKind.Utc, item.ObservedAt.Kind);
        Assert.False(item.IsStale);
    }

    [Fact]
    public async Task A_store_without_prices_gives_an_empty_list_not_an_error()
    {
        var store = await AddStoreAsync();

        var response = await _client.GetAsync($"/api/v1/stores/{store}/prices");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = (await response.Content.ReadFromJsonAsync<StorePricesResponse>())!;
        Assert.Empty(body.Items);
        Assert.Equal(0, body.Total);
        Assert.Equal(store, body.Store.Id);
    }

    [Fact]
    public async Task An_unknown_store_is_404_with_an_error_dto()
    {
        var response = await _client.GetAsync("/api/v1/stores/999999/prices");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.NotFound, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }

    [Fact]
    public async Task Of_two_prices_for_one_product_the_newest_is_returned()
    {
        var store = await AddStoreAsync();
        var product = await AddProductAsync("Utenos Originalus", 500);
        await AddPriceAsync(store, product, 100, Now.AddDays(-5));
        var newest = await AddPriceAsync(store, product, 120, Now.AddDays(-1));
        await AddPriceAsync(store, product, 90, Now.AddDays(-9));

        var item = Assert.Single((await GetPricesAsync(store)).Items);

        Assert.Equal(newest, item.PriceEntryId);
        Assert.Equal(120, item.PriceCents);
    }

    [Fact]
    public async Task When_observed_at_ties_the_higher_id_wins()
    {
        var store = await AddStoreAsync();
        var product = await AddProductAsync("Tauras Tradicinis", 500);
        var observed = Now.AddDays(-1);
        await AddPriceAsync(store, product, 100, observed);
        var later = await AddPriceAsync(store, product, 110, observed);

        var item = Assert.Single((await GetPricesAsync(store)).Items);

        Assert.Equal(later, item.PriceEntryId);
    }

    [Fact]
    public async Task Rejected_entries_are_left_out_and_never_hide_an_older_valid_price()
    {
        var store = await AddStoreAsync();
        var onlyRejected = await AddProductAsync("Heineken", 500);
        var mixed = await AddProductAsync("Carlsberg", 500);
        await AddPriceAsync(store, onlyRejected, 50, Now.AddDays(-1), PriceStatus.Rejected);
        var valid = await AddPriceAsync(store, mixed, 149, Now.AddDays(-3));
        await AddPriceAsync(store, mixed, 1, Now.AddDays(-1), PriceStatus.Rejected); // newer but wrong
        await AddPriceAsync(store, mixed, 2, Now.AddHours(-1), PriceStatus.Pending); // not confirmed yet

        var body = await GetPricesAsync(store);

        var item = Assert.Single(body.Items);
        Assert.Equal(valid, item.PriceEntryId);
        Assert.Equal(1, body.Total);
    }

    [Fact]
    public async Task Prices_are_paged_in_a_stable_order()
    {
        var store = await AddStoreAsync();
        // Same name twice (330 ml first, then 500 ml), then other names.
        foreach (var (name, volume) in new[]
                 {
                     ("Dundulis", 500), ("Dundulis", 330), ("Ąžuolas", 500), ("Kalnapilis", 500), ("Biržų", 500),
                 })
        {
            await AddPriceAsync(store, await AddProductAsync(name, volume), 150, Now.AddDays(-1));
        }

        var page1 = await GetPricesAsync(store, "page=1&pageSize=2");
        var page2 = await GetPricesAsync(store, "page=2&pageSize=2");
        var page3 = await GetPricesAsync(store, "page=3&pageSize=2");
        var beyond = await GetPricesAsync(store, "page=4&pageSize=2");

        Assert.All(new[] { page1, page2, page3, beyond }, p => Assert.Equal(5, p.Total));
        Assert.Equal([2, 2, 1, 0], new[] { page1, page2, page3, beyond }.Select(p => p.Items.Count));
        Assert.Equal(
            ["Ąžuolas 500", "Biržų 500", "Dundulis 330", "Dundulis 500", "Kalnapilis 500"],
            new[] { page1, page2, page3 }.SelectMany(p => p.Items).Select(i => $"{i.ProductName} {i.VolumeMl}"));
        Assert.Equal(2, page2.Page);
        Assert.Equal(2, page2.PageSize);
    }

    [Theory]
    [InlineData("page=0", HttpStatusCode.UnprocessableEntity)]
    [InlineData("page=-1", HttpStatusCode.UnprocessableEntity)]
    [InlineData("pageSize=0", HttpStatusCode.UnprocessableEntity)]
    [InlineData("pageSize=101", HttpStatusCode.UnprocessableEntity)]
    [InlineData("pageSize=100", HttpStatusCode.OK)]
    [InlineData("pageSize=1", HttpStatusCode.OK)]
    [InlineData("page=abc", HttpStatusCode.BadRequest)]
    public async Task Bad_paging_values_are_rejected_with_an_error_dto(string query, HttpStatusCode expected)
    {
        var store = await AddStoreAsync();

        var response = await _client.GetAsync($"/api/v1/stores/{store}/prices?{query}");

        Assert.Equal(expected, response.StatusCode);
        if (expected != HttpStatusCode.OK)
        {
            Assert.False(string.IsNullOrEmpty((await response.Content.ReadFromJsonAsync<ErrorDto>())!.RequestId));
        }
    }

    [Fact]
    public async Task A_price_is_stale_only_when_older_than_exactly_seven_days_by_server_time()
    {
        var store = await AddStoreAsync();
        var exactly = await AddProductAsync("A exactly 7 days", 500);
        var over = await AddProductAsync("B 7 days and 1 second", 500);
        var under = await AddProductAsync("C just under 7 days", 500);
        await AddPriceAsync(store, exactly, 100, Now.AddDays(-7));
        await AddPriceAsync(store, over, 100, Now.AddDays(-7).AddSeconds(-1));
        await AddPriceAsync(store, under, 100, Now.AddDays(-7).AddSeconds(1));

        var stale = (await GetPricesAsync(store)).Items.ToDictionary(i => i.ProductName, i => i.IsStale);

        Assert.False(stale["A exactly 7 days"]);
        Assert.True(stale["B 7 days and 1 second"]);
        Assert.False(stale["C just under 7 days"]);
    }

    [Fact]
    public async Task Staleness_follows_the_server_clock_and_does_not_change_the_entry()
    {
        var store = await AddStoreAsync();
        var product = await AddProductAsync("Rinkuškiai Ekstra", 500);
        var entry = await AddPriceAsync(store, product, 155, Now.AddDays(-6));

        Assert.False(Assert.Single((await GetPricesAsync(store)).Items).IsStale);
        _clock.Advance(TimeSpan.FromDays(2));
        Assert.True(Assert.Single((await GetPricesAsync(store)).Items).IsStale);

        await using var db = _database.CreateContext();
        var stored = await db.PriceEntries.AsNoTracking().SingleAsync(p => p.Id == entry);
        Assert.Equal(PriceStatus.Approved, stored.Status);
        Assert.Equal(155, stored.PriceCents);
    }

    [Fact]
    public async Task The_query_is_three_statements_however_many_products_and_uses_the_price_indexes()
    {
        var store = await AddStoreAsync();
        for (var i = 0; i < 12; i++)
        {
            var product = await AddProductAsync($"Produktas {i:00}", 500);
            await AddPriceAsync(store, product, 100 + i, Now.AddDays(-1));
            await AddPriceAsync(store, product, 200 + i, Now.AddDays(-2));
        }

        // No N+1: store lookup, count and one page, nothing per product.
        var counter = new CommandCounter();
        await using (var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
                         .UseAlusekisSqlite(_database.ConnectionString)
                         .AddInterceptors(counter)
                         .Options))
        {
            var result = await StorePrices.QueryAsync(db, Now, store, 1, 20, CancellationToken.None);
            Assert.Equal(12, result!.Items.Count);
        }

        Assert.Equal(3, counter.Count);

        // The plan searches both PriceEntries indexes instead of scanning the table.
        await using var planDb = _database.CreateContext();
        var sql = StorePrices.LatestApproved(planDb, store).ToQueryString()
            .Split('\n')
            .Where(line => !line.StartsWith(".param"))
            .Aggregate((a, b) => a + "\n" + b)
            .Replace("@__storeId_0", store.ToString());
        var connection = planDb.Database.GetDbConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "EXPLAIN QUERY PLAN " + sql;
        var plan = new List<string>();
        await using (var reader = await command.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
            {
                plan.Add(reader.GetString(3));
            }
        }

        var text = string.Join(" | ", plan);
        Assert.Contains("IX_PriceEntries_StoreId", text);
        Assert.Contains("IX_PriceEntries_Product_Store_Status_ObservedAt_Id", text);
        Assert.DoesNotContain(plan, line => line.StartsWith("SCAN"));
    }

    // ---------- helpers ----------

    private async Task<StorePricesResponse> GetPricesAsync(long storeId, string query = "") =>
        (await _client.GetFromJsonAsync<StorePricesResponse>($"/api/v1/stores/{storeId}/prices?{query}"))!;

    private async Task<long> AddStoreAsync(string name = "Maxima XX", string address = "Ukmergės g. 282")
    {
        await using var db = _database.CreateContext();
        if (_cityId is null)
        {
            var city = new City { Name = "Vilnius", NormalizedName = "vilnius" };
            db.Cities.Add(city);
            await db.SaveChangesAsync();
            _cityId = city.Id;
        }

        var store = new Store { CityId = _cityId.Value, Name = name, Address = address, CreatedAt = Now };
        db.Stores.Add(store);
        await db.SaveChangesAsync();
        return store.Id;
    }

    private async Task<long> AddProductAsync(string name, int volumeMl)
    {
        await using var db = _database.CreateContext();
        var product = new Product
        {
            Name = name,
            NormalizedName = TextNormalizer.NormalizeName(name),
            VolumeMl = volumeMl,
            CreatedAt = Now,
        };
        db.Products.Add(product);
        await db.SaveChangesAsync();
        return product.Id;
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

    private sealed class CommandCounter : DbCommandInterceptor
    {
        private int _count;

        public int Count => _count;

        public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
            DbCommand command,
            CommandEventData eventData,
            InterceptionResult<DbDataReader> result,
            CancellationToken cancellationToken = default)
        {
            Interlocked.Increment(ref _count);
            return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
        }
    }
}
