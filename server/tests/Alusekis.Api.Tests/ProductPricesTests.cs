using System.Data.Common;
using System.Net;
using System.Net.Http.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Alusekis.Api.Products;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace Alusekis.Api.Tests;

public sealed class ProductPricesTests : IDisposable
{
    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;
    private long? _cityId;

    public ProductPricesTests()
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
    public async Task Two_products_in_two_stores_are_compared_cheapest_first_or_dearest_first()
    {
        var a = await AddStoreAsync("Maxima XX", "Ukmergės g. 282");
        var b = await AddStoreAsync("Lidl", "Kalvarijų g. 202");
        var beer = await AddProductAsync("Švyturys Ekstra", 500);
        var other = await AddProductAsync("Utenos Originalus", 500);
        await AddPriceAsync(a, beer, 170, Now.AddDays(-4)); // superseded
        var beerA = await AddPriceAsync(a, beer, 150, Now.AddDays(-1));
        var beerB = await AddPriceAsync(b, beer, 120, Now.AddDays(-2));
        await AddPriceAsync(a, other, 100, Now.AddDays(-1));
        await AddPriceAsync(b, other, 200, Now.AddDays(-1));

        var asc = await GetAsync(beer, "asc");
        var desc = await GetAsync(beer, "desc");
        var otherAsc = await GetAsync(other, "asc");

        Assert.Equal(new ProductSummaryDto(beer, "Švyturys Ekstra", null, 500), asc.Product);
        Assert.Equal([b, a], asc.Items.Select(i => i.StoreId));
        Assert.Equal([a, b], desc.Items.Select(i => i.StoreId));
        Assert.Equal([120, 150], asc.Items.Select(i => i.PriceCents));
        Assert.Equal(2, asc.StoreCount);
        Assert.False(asc.SingleStore);

        var first = asc.Items[0];
        Assert.Equal(beerB, first.PriceEntryId);
        Assert.Equal("Lidl", first.StoreName);
        Assert.Equal("Kalvarijų g. 202", first.StoreAddress);
        Assert.Equal(Now.AddDays(-2), first.ObservedAt);
        Assert.Equal(DateTimeKind.Utc, first.ObservedAt.Kind);
        Assert.False(first.IsStale);
        Assert.Equal(beerA, asc.Items[1].PriceEntryId);

        // The other product is its own comparison, untouched by the first one.
        Assert.Equal([100, 200], otherAsc.Items.Select(i => i.PriceCents));
        Assert.Equal([a, b], otherAsc.Items.Select(i => i.StoreId));
    }

    [Theory]
    [InlineData("")]
    [InlineData("?sort=asc")]
    [InlineData("?sort=ASC")]
    public async Task Ascending_is_the_default_and_sort_ignores_letter_case(string query)
    {
        var (product, cheap, dear) = await TwoStoreProductAsync();

        var result = await GetRawAsync(product, query);

        Assert.Equal([cheap, dear], result.Items.Select(i => i.StoreId));
    }

    [Fact]
    public async Task Sort_desc_in_any_letter_case_puts_the_dearest_first()
    {
        var (product, cheap, dear) = await TwoStoreProductAsync();

        Assert.Equal([dear, cheap], (await GetRawAsync(product, "?sort=desc")).Items.Select(i => i.StoreId));
        Assert.Equal([dear, cheap], (await GetRawAsync(product, "?sort=DeSc")).Items.Select(i => i.StoreId));
    }

    [Theory]
    [InlineData("?sort=sideways")]
    [InlineData("?sort=")]
    [InlineData("?sort=ascending")]
    [InlineData("?sort=1")]
    public async Task A_bad_sort_is_rejected_with_an_error_dto(string query)
    {
        var (product, _, _) = await TwoStoreProductAsync();

        var response = await _client.GetAsync($"/api/v1/products/{product}/prices{query}");

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.ValidationFailed, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }

    [Fact]
    public async Task Equal_prices_are_ordered_by_store_id_in_both_directions()
    {
        var x = await AddStoreAsync("X", "Gatvė 1");
        var y = await AddStoreAsync("Y", "Gatvė 2");
        var z = await AddStoreAsync("Z", "Gatvė 3");
        var product = await AddProductAsync("Alus", 500);
        // Inserted out of order on purpose: the order must come from the store id.
        await AddPriceAsync(z, product, 100, Now.AddDays(-1));
        await AddPriceAsync(x, product, 100, Now.AddDays(-1));
        await AddPriceAsync(y, product, 100, Now.AddDays(-1));

        Assert.Equal([x, y, z], (await GetAsync(product, "asc")).Items.Select(i => i.StoreId));
        Assert.Equal([x, y, z], (await GetAsync(product, "desc")).Items.Select(i => i.StoreId));
    }

    [Fact]
    public async Task Only_one_store_is_flagged_as_nothing_to_compare_but_the_price_is_still_returned()
    {
        var store = await AddStoreAsync("Maxima XX", "Ukmergės g. 282");
        var product = await AddProductAsync("Alus", 500);
        await AddPriceAsync(store, product, 149, Now.AddDays(-1));

        var result = await GetAsync(product, "asc");

        Assert.True(result.SingleStore);
        Assert.Equal(1, result.StoreCount);
        Assert.Equal(149, Assert.Single(result.Items).PriceCents);
    }

    [Fact]
    public async Task A_product_without_prices_gives_an_empty_list_not_an_error()
    {
        var product = await AddProductAsync("Alus be kainų", 500, brand: "Testas");

        var response = await _client.GetAsync($"/api/v1/products/{product}/prices");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = (await response.Content.ReadFromJsonAsync<ProductPricesResponse>())!;
        Assert.Empty(result.Items);
        Assert.Equal(0, result.StoreCount);
        Assert.False(result.SingleStore);
        Assert.Equal(new ProductSummaryDto(product, "Alus be kainų", "Testas", 500), result.Product);
    }

    [Fact]
    public async Task An_unknown_product_is_404_with_an_error_dto()
    {
        var response = await _client.GetAsync("/api/v1/products/999999/prices");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.NotFound, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync("/api/v1/products/abc/prices")).StatusCode);
    }

    [Fact]
    public async Task Rejected_and_unconfirmed_entries_are_left_out()
    {
        var a = await AddStoreAsync("A", "Gatvė 1");
        var b = await AddStoreAsync("B", "Gatvė 2");
        var product = await AddProductAsync("Alus", 500);
        var valid = await AddPriceAsync(a, product, 150, Now.AddDays(-3));
        await AddPriceAsync(a, product, 10, Now.AddDays(-1), PriceStatus.Rejected); // wrong: must not win
        await AddPriceAsync(a, product, 5, Now.AddHours(-1), PriceStatus.Pending); // not confirmed
        await AddPriceAsync(b, product, 1, Now.AddDays(-1), PriceStatus.Rejected); // only a wrong entry

        var result = await GetAsync(product, "asc");

        var item = Assert.Single(result.Items);
        Assert.Equal(valid, item.PriceEntryId);
        Assert.Equal(150, item.PriceCents);
        Assert.Equal(1, result.StoreCount);
    }

    [Fact]
    public async Task Of_two_entries_for_one_store_the_newest_is_taken_and_ties_go_to_the_higher_id()
    {
        var a = await AddStoreAsync("A", "Gatvė 1");
        var b = await AddStoreAsync("B", "Gatvė 2");
        var product = await AddProductAsync("Alus", 500);
        await AddPriceAsync(a, product, 100, Now.AddDays(-5));
        var newest = await AddPriceAsync(a, product, 130, Now.AddDays(-1));
        await AddPriceAsync(a, product, 90, Now.AddDays(-9));
        var tieTime = Now.AddDays(-2);
        await AddPriceAsync(b, product, 200, tieTime);
        var tieWinner = await AddPriceAsync(b, product, 210, tieTime);

        var items = (await GetAsync(product, "asc")).Items.ToDictionary(i => i.StoreId);

        Assert.Equal(newest, items[a].PriceEntryId);
        Assert.Equal(130, items[a].PriceCents);
        Assert.Equal(tieWinner, items[b].PriceEntryId);
        Assert.Equal(210, items[b].PriceCents);
    }

    [Fact]
    public async Task The_same_name_with_another_volume_is_a_different_product_and_is_not_mixed_in()
    {
        var a = await AddStoreAsync("A", "Gatvė 1");
        var b = await AddStoreAsync("B", "Gatvė 2");
        var small = await AddProductAsync("Heineken", 330);
        var large = await AddProductAsync("Heineken", 500);
        await AddPriceAsync(a, small, 80, Now.AddDays(-1)); // cheaper, but a different pack size
        await AddPriceAsync(b, small, 90, Now.AddDays(-1));
        await AddPriceAsync(a, large, 160, Now.AddDays(-1));
        await AddPriceAsync(b, large, 150, Now.AddDays(-1));

        var largeResult = await GetAsync(large, "asc");
        var smallResult = await GetAsync(small, "asc");

        Assert.NotEqual(small, large);
        Assert.Equal(500, largeResult.Product.VolumeMl);
        Assert.Equal([150, 160], largeResult.Items.Select(i => i.PriceCents));
        Assert.Equal(330, smallResult.Product.VolumeMl);
        Assert.Equal([80, 90], smallResult.Items.Select(i => i.PriceCents));
    }

    [Fact]
    public async Task A_price_is_stale_only_when_older_than_exactly_seven_days_by_server_time()
    {
        var exactly = await AddStoreAsync("Tiksliai 7 d.", "Gatvė 1");
        var over = await AddStoreAsync("7 d. ir 1 s.", "Gatvė 2");
        var under = await AddStoreAsync("Beveik 7 d.", "Gatvė 3");
        var product = await AddProductAsync("Alus", 500);
        await AddPriceAsync(exactly, product, 100, Now.AddDays(-7));
        await AddPriceAsync(over, product, 100, Now.AddDays(-7).AddSeconds(-1));
        await AddPriceAsync(under, product, 100, Now.AddDays(-7).AddSeconds(1));

        var stale = (await GetAsync(product, "asc")).Items.ToDictionary(i => i.StoreId, i => i.IsStale);

        Assert.False(stale[exactly]);
        Assert.True(stale[over]);
        Assert.False(stale[under]);
    }

    [Fact]
    public async Task The_comparison_takes_two_statements_however_many_stores()
    {
        var product = await AddProductAsync("Alus", 500);
        for (var i = 0; i < 12; i++)
        {
            var store = await AddStoreAsync($"Parduotuvė {i:00}", $"Gatvė {i}");
            await AddPriceAsync(store, product, 100 + i, Now.AddDays(-1));
            await AddPriceAsync(store, product, 200 + i, Now.AddDays(-2));
        }

        var counter = new CommandCounter();
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseAlusekisSqlite(_database.ConnectionString)
            .AddInterceptors(counter)
            .Options);

        var result = await ProductPrices.QueryAsync(db, Now, product, descending: false, CancellationToken.None);

        Assert.Equal(12, result!.Items.Count);
        Assert.Equal(2, counter.Count); // the product, then all its prices; nothing per store
    }

    // ---------- helpers ----------

    /// <summary>One product with the cheaper price in the store with the higher id.</summary>
    private async Task<(long Product, long Cheap, long Dear)> TwoStoreProductAsync()
    {
        var dear = await AddStoreAsync("Brangi", "Gatvė 1");
        var cheap = await AddStoreAsync("Pigi", "Gatvė 2");
        var product = await AddProductAsync("Alus", 500);
        await AddPriceAsync(dear, product, 200, Now.AddDays(-1));
        await AddPriceAsync(cheap, product, 100, Now.AddDays(-1));
        return (product, cheap, dear);
    }

    private Task<ProductPricesResponse> GetAsync(long productId, string sort) =>
        GetRawAsync(productId, $"?sort={sort}");

    private async Task<ProductPricesResponse> GetRawAsync(long productId, string query)
    {
        var response = await _client.GetAsync($"/api/v1/products/{productId}/prices{query}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<ProductPricesResponse>())!;
    }

    private async Task<long> AddProductAsync(string name, int volumeMl, string? brand = null)
    {
        await using var db = _database.CreateContext();
        var product = new Product
        {
            Name = name,
            NormalizedName = TextNormalizer.NormalizeName(name),
            VolumeMl = volumeMl,
            Brand = brand,
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
