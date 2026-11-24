using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Products;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Alusekis.Api.Tests;

public sealed class PriceHistoryTests : IDisposable
{
    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;
    private long? _cityId;

    public PriceHistoryTests()
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

    // ---------- the 7 / 30 / 90 day window ----------

    [Theory]
    [InlineData(7)]
    [InlineData(30)]
    [InlineData(90)]
    public async Task The_window_includes_an_entry_exactly_on_the_edge_and_excludes_one_just_outside(int days)
    {
        var (store, product) = await StoreAndProductAsync();
        var justOutside = await AddPriceAsync(store, product, 100, Now.AddDays(-days).AddSeconds(-1));
        var exactlyOnEdge = await AddPriceAsync(store, product, 110, Now.AddDays(-days));
        var justInside = await AddPriceAsync(store, product, 120, Now.AddDays(-days).AddSeconds(1));
        var recent = await AddPriceAsync(store, product, 130, Now.AddHours(-1));

        var result = await GetAsync(product, store, $"?days={days}");

        Assert.Equal([exactlyOnEdge, justInside, recent], result.Items.Select(i => i.PriceEntryId));
        Assert.DoesNotContain(justOutside, result.Items.Select(i => i.PriceEntryId));
        Assert.Equal(days, result.Days);
        Assert.Equal(Now.AddDays(-days), result.From);
        Assert.Equal(Now, result.To);
        Assert.Equal(DateTimeKind.Utc, result.From.Kind);
    }

    [Fact]
    public async Task Each_window_is_its_own_length()
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 100, Now.AddDays(-80));
        await AddPriceAsync(store, product, 110, Now.AddDays(-20));
        await AddPriceAsync(store, product, 120, Now.AddDays(-3));

        Assert.Equal([120], (await GetAsync(product, store, "?days=7")).Items.Select(i => i.PriceCents));
        Assert.Equal([110, 120], (await GetAsync(product, store, "?days=30")).Items.Select(i => i.PriceCents));
        Assert.Equal([100, 110, 120], (await GetAsync(product, store, "?days=90")).Items.Select(i => i.PriceCents));
    }

    [Fact]
    public async Task A_missing_days_means_30()
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 100, Now.AddDays(-31));
        await AddPriceAsync(store, product, 110, Now.AddDays(-29));

        var result = await GetAsync(product, store, "");

        Assert.Equal(30, result.Days);
        Assert.Equal([110], result.Items.Select(i => i.PriceCents));
    }

    [Theory]
    [InlineData("?days=")]
    [InlineData("?days=abc")]
    [InlineData("?days=0")]
    [InlineData("?days=-7")]
    [InlineData("?days=1")]
    [InlineData("?days=8")]
    [InlineData("?days=29")]
    [InlineData("?days=31")]
    [InlineData("?days=365")]
    [InlineData("?days=7.0")]
    [InlineData("?days=07")]
    [InlineData("?days=%2030")]
    public async Task Any_other_days_is_rejected_with_an_error_dto(string query)
    {
        var (store, product) = await StoreAndProductAsync();

        var response = await _client.GetAsync($"/api/v1/products/{product}/stores/{store}/history{query}");

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.ValidationFailed, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }

    // ---------- how many entries ----------

    [Fact]
    public async Task No_entries_in_the_window_is_an_empty_list_not_an_error()
    {
        var (store, product) = await StoreAndProductAsync();
        await AddPriceAsync(store, product, 100, Now.AddDays(-200)); // far too old

        var response = await _client.GetAsync($"/api/v1/products/{product}/stores/{store}/history?days=90");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = (await response.Content.ReadFromJsonAsync<PriceHistoryResponse>())!;
        Assert.Empty(result.Items);
        Assert.Equal("Maxima XX", result.Store.Name);
        Assert.Equal("Alus", result.Product.Name);
    }

    [Fact]
    public async Task One_entry_is_a_list_with_one_point()
    {
        var (store, product) = await StoreAndProductAsync();
        var only = await AddPriceAsync(store, product, 149, Now.AddDays(-2));

        var result = await GetAsync(product, store, "?days=7");

        var point = Assert.Single(result.Items);
        Assert.Equal(only, point.PriceEntryId);
        Assert.Equal(149, point.PriceCents);
        Assert.Equal(Now.AddDays(-2), point.ObservedAt);
        Assert.Equal(DateTimeKind.Utc, point.ObservedAt.Kind);
    }

    [Fact]
    public async Task The_same_price_in_several_entries_stays_several_points()
    {
        var (store, product) = await StoreAndProductAsync();
        var t = Now.AddDays(-5);
        await AddPriceAsync(store, product, 150, t);
        await AddPriceAsync(store, product, 150, t.AddDays(1));
        await AddPriceAsync(store, product, 150, t.AddDays(1)); // even at the very same moment
        await AddPriceAsync(store, product, 150, t.AddDays(2));

        var result = await GetAsync(product, store, "?days=7");

        Assert.Equal(4, result.Items.Count); // not merged, not deduplicated, nothing added
        Assert.All(result.Items, i => Assert.Equal(150, i.PriceCents));
        Assert.Equal(4, result.Items.Select(i => i.PriceEntryId).Distinct().Count());
    }

    // ---------- which entries ----------

    [Fact]
    public async Task Rejected_and_unconfirmed_entries_are_left_out()
    {
        var (store, product) = await StoreAndProductAsync();
        var valid = await AddPriceAsync(store, product, 150, Now.AddDays(-3));
        await AddPriceAsync(store, product, 10, Now.AddDays(-2), PriceStatus.Rejected);
        await AddPriceAsync(store, product, 5, Now.AddDays(-1), PriceStatus.Pending);

        var result = await GetAsync(product, store, "?days=7");

        Assert.Equal(valid, Assert.Single(result.Items).PriceEntryId);
    }

    [Fact]
    public async Task Only_this_product_in_this_store_is_returned()
    {
        var a = await AddStoreAsync("Maxima XX", "Ukmergės g. 282");
        var b = await AddStoreAsync("Lidl", "Kalvarijų g. 202");
        var small = await AddProductAsync("Heineken", 330);
        var large = await AddProductAsync("Heineken", 500);
        var mine = await AddPriceAsync(a, large, 160, Now.AddDays(-1));
        await AddPriceAsync(b, large, 150, Now.AddDays(-1)); // other store
        await AddPriceAsync(a, small, 80, Now.AddDays(-1)); // other volume: another product

        var result = await GetAsync(large, a, "?days=7");

        Assert.Equal(mine, Assert.Single(result.Items).PriceEntryId);
        Assert.Equal(500, result.Product.VolumeMl);
        Assert.Equal(a, result.Store.Id);
    }

    [Fact]
    public async Task Entries_come_oldest_first_whatever_order_they_were_recorded_in()
    {
        var (store, product) = await StoreAndProductAsync();
        var newest = await AddPriceAsync(store, product, 130, Now.AddDays(-1));
        var oldest = await AddPriceAsync(store, product, 110, Now.AddDays(-6));
        var middle = await AddPriceAsync(store, product, 120, Now.AddDays(-3));
        var tieFirst = await AddPriceAsync(store, product, 140, Now.AddDays(-2));
        var tieSecond = await AddPriceAsync(store, product, 141, Now.AddDays(-2));

        var result = await GetAsync(product, store, "?days=7");

        Assert.Equal([oldest, middle, tieFirst, tieSecond, newest], result.Items.Select(i => i.PriceEntryId));
        Assert.Equal(result.Items.OrderBy(i => i.ObservedAt).Select(i => i.ObservedAt), result.Items.Select(i => i.ObservedAt));
    }

    // ---------- not found ----------

    [Fact]
    public async Task An_unknown_product_is_404_with_an_error_dto()
    {
        var (store, _) = await StoreAndProductAsync();

        var response = await _client.GetAsync($"/api/v1/products/999999/stores/{store}/history");

        await AssertNotFoundAsync(response);
    }

    [Fact]
    public async Task An_unknown_store_is_404_with_an_error_dto()
    {
        var (_, product) = await StoreAndProductAsync();

        var response = await _client.GetAsync($"/api/v1/products/{product}/stores/999999/history");

        await AssertNotFoundAsync(response);
    }

    [Fact]
    public async Task Ids_that_are_not_numbers_are_404()
    {
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync("/api/v1/products/abc/stores/1/history")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync("/api/v1/products/1/stores/abc/history")).StatusCode);
    }

    // ---------- the query ----------

    [Fact]
    public async Task The_history_takes_three_statements_and_walks_the_price_index_in_order()
    {
        var (store, product) = await StoreAndProductAsync();
        for (var i = 0; i < 12; i++)
        {
            await AddPriceAsync(store, product, 100 + i, Now.AddDays(-i));
        }

        var counter = new CommandCounter();
        await using (var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
                         .UseAlusekisSqlite(_database.ConnectionString)
                         .AddInterceptors(counter)
                         .Options))
        {
            var outcome = await PriceHistory.QueryAsync(db, Now, product, store, 30, CancellationToken.None);
            Assert.Equal(12, outcome.Response!.Items.Count);
        }

        Assert.Equal(3, counter.Count); // product, store, entries: nothing per entry

        await using var planDb = _database.CreateContext();
        var plan = await ExplainAsync(planDb, PriceHistory.EntriesSince(planDb, product, store, Now.AddDays(-30)).ToQueryString());
        var text = string.Join(" | ", plan);

        Assert.Contains("IX_PriceEntries_Product_Store_Status_ObservedAt_Id", text);
        Assert.DoesNotContain(plan, line => line.StartsWith("SCAN"));
        Assert.DoesNotContain("TEMP B-TREE", text); // already in ObservedAt, Id order
    }

    // ---------- helpers ----------

    private async Task<(long Store, long Product)> StoreAndProductAsync()
    {
        var store = await AddStoreAsync("Maxima XX", "Ukmergės g. 282");
        var product = await AddProductAsync("Alus", 500);
        return (store, product);
    }

    private async Task<PriceHistoryResponse> GetAsync(long product, long store, string query)
    {
        var response = await _client.GetAsync($"/api/v1/products/{product}/stores/{store}/history{query}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<PriceHistoryResponse>())!;
    }

    private static async Task AssertNotFoundAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.NotFound, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }

    /// <summary>EXPLAIN QUERY PLAN of an EF query, with its parameters written into the SQL.</summary>
    private static async Task<List<string>> ExplainAsync(AppDbContext db, string queryString)
    {
        var parameters = new Dictionary<string, string>();
        var sqlLines = new List<string>();
        foreach (var line in queryString.Split('\n'))
        {
            var match = Regex.Match(line.TrimEnd('\r'), @"^\.param set (@\S+) (.+)$");
            if (match.Success)
            {
                parameters[match.Groups[1].Value] = match.Groups[2].Value;
            }
            else
            {
                sqlLines.Add(line);
            }
        }

        var sql = string.Join("\n", sqlLines);
        foreach (var (name, value) in parameters.OrderByDescending(p => p.Key.Length))
        {
            sql = sql.Replace(name, value);
        }

        var connection = db.Database.GetDbConnection();
        await connection.OpenAsync();
        await using var command = connection.CreateCommand();
        command.CommandText = "EXPLAIN QUERY PLAN " + sql;
        var plan = new List<string>();
        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            plan.Add(reader.GetString(3));
        }

        return plan;
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

    private async Task<long> AddStoreAsync(string name, string address)
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
