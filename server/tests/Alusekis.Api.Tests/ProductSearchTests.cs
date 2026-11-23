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

public sealed class ProductSearchTests : IDisposable
{
    private readonly TestDatabase _database = new();
    private readonly FakeClock _clock = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;
    private long? _cityId;

    public ProductSearchTests()
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

    // ---------- matching ----------

    [Theory]
    [InlineData("švyturys")]
    [InlineData("ŠVYTURYS")]
    [InlineData("Švyturys")]
    [InlineData("svyturys")]
    [InlineData("ŠvYtUrYs")]
    [InlineData("tury")] // part of the name
    public async Task Search_ignores_letter_case_and_finds_part_of_a_name(string query)
    {
        await AddProductAsync("Švyturys Ekstra", 500);

        var items = await SearchAsync(query);

        Assert.Equal("Švyturys Ekstra", Assert.Single(items).Name);
    }

    [Theory]
    [InlineData("žalgiris", "Žalgiris")]
    [InlineData("ŽALGIRIS", "Žalgiris")]
    [InlineData("Zalgiris", "Žalgiris")]
    [InlineData("ąžuolas", "Ąžuolas Čempionas")]
    [InlineData("AZUOLAS", "Ąžuolas Čempionas")]
    [InlineData("čempionas", "Ąžuolas Čempionas")]
    [InlineData("ęėįšųūž", "Ęėįšųūž Tikrinimas")]
    public async Task Lithuanian_letters_match_with_and_without_diacritics(string query, string expected)
    {
        await AddProductAsync("Žalgiris", 500);
        await AddProductAsync("Ąžuolas Čempionas", 500);
        await AddProductAsync("Ęėįšųūž Tikrinimas", 500);

        var items = await SearchAsync(query);

        Assert.Equal(expected, Assert.Single(items).Name);
    }

    [Fact]
    public async Task Spaces_around_the_query_are_ignored()
    {
        await AddProductAsync("Švyturys Ekstra", 500);

        Assert.Single(await SearchAsync("   švyturys   "));
        Assert.Single(await SearchAsync("\tŠVYTURYS\n"));
    }

    [Fact]
    public async Task No_match_gives_an_empty_list_not_an_error()
    {
        await AddProductAsync("Švyturys Ekstra", 500);

        var response = await _client.GetAsync("/api/v1/products/search?q=nera-tokio");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<ProductSearchResponse>())!.Items);
    }

    // ---------- query length ----------

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("a")]
    [InlineData("  a  ")] // one character after trimming
    [InlineData("ž")]
    public async Task A_query_under_two_characters_is_rejected(string query)
    {
        var response = await _client.GetAsync($"/api/v1/products/search?q={Uri.EscapeDataString(query)}");

        await AssertValidationErrorAsync(response);
    }

    [Fact]
    public async Task A_missing_query_is_rejected()
    {
        await AssertValidationErrorAsync(await _client.GetAsync("/api/v1/products/search"));
    }

    [Theory]
    [InlineData("ab")]
    [InlineData("  ab  ")]
    public async Task Two_characters_work(string query)
    {
        await AddProductAsync("Abraka", 500);

        Assert.Single(await SearchAsync(query));
    }

    [Fact]
    public async Task The_limit_is_100_characters_after_trimming()
    {
        var at100 = new string('a', 100);

        var ok = await _client.GetAsync($"/api/v1/products/search?q={at100}");
        var padded = await _client.GetAsync($"/api/v1/products/search?q=%20%20{at100}%20%20");
        var over = await _client.GetAsync($"/api/v1/products/search?q={at100}a");

        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        Assert.Equal(HttpStatusCode.OK, padded.StatusCode);
        await AssertValidationErrorAsync(over);
    }

    // ---------- special characters ----------

    [Fact]
    public async Task Percent_underscore_and_quote_are_plain_characters_and_break_nothing()
    {
        await AddProductAsync("100% Alus", 500);
        await AddProductAsync("Alus_Ekstra", 500);
        await AddProductAsync("Alus Xekstra", 500);
        await AddProductAsync("O'Brien Stout", 500);
        await AddProductAsync("Paprastas", 500);

        Assert.Equal("100% Alus", Assert.Single(await SearchAsync("0%")).Name); // a real percent sign
        Assert.Empty(await SearchAsync("u%e")); // would match several names if % were a wildcard
        Assert.Equal("Alus_Ekstra", Assert.Single(await SearchAsync("s_e")).Name); // not "any character" ("Alus Xekstra" has no _)
        Assert.Equal("O'Brien Stout", Assert.Single(await SearchAsync("o'brien")).Name);
        Assert.Empty(await SearchAsync("%%"));
        Assert.Empty(await SearchAsync("_%"));
        Assert.Equal("O'Brien Stout", Assert.Single(await SearchAsync("'b")).Name);
    }

    [Fact]
    public async Task SQL_text_is_just_text()
    {
        await AddProductAsync("Paprastas", 500);

        var items = await SearchAsync("'; DROP TABLE Products; --");

        Assert.Empty(items);
        await using var db = _database.CreateContext();
        Assert.Equal(1, await db.Products.CountAsync()); // the table is still there
    }

    [Fact]
    public async Task A_query_made_only_of_combining_marks_does_not_match_everything()
    {
        await AddProductAsync("Paprastas", 500);

        // Two combining accents: 2 characters long, but nothing once diacritics are removed.
        Assert.Empty(await SearchAsync("́́"));
    }

    // ---------- order and limit ----------

    [Fact]
    public async Task Names_starting_with_the_query_come_first_then_by_name_and_volume()
    {
        await AddProductAsync("Dark Utenos Porteris", 500); // contains, does not start
        await AddProductAsync("Utenos Originalus", 1000);
        await AddProductAsync("Utenos Originalus", 500);
        await AddProductAsync("Utenos Dark", 500);
        await AddProductAsync("Rinkuškiai Utenos", 500); // contains, does not start

        var items = await SearchAsync("utenos");

        Assert.Equal(
            ["Utenos Dark 500", "Utenos Originalus 500", "Utenos Originalus 1000", "Dark Utenos Porteris 500", "Rinkuškiai Utenos 500"],
            items.Select(i => $"{i.Name} {i.VolumeMl}"));
    }

    [Fact]
    public async Task At_most_50_results_are_returned()
    {
        for (var i = 0; i < 60; i++)
        {
            await AddProductAsync($"Alus {i:00}", 500);
        }

        var items = await SearchAsync("alus");

        Assert.Equal(50, items.Count);
        Assert.Equal("Alus 00", items[0].Name);
        Assert.Equal("Alus 49", items[^1].Name);
    }

    // ---------- lowest price ----------

    [Fact]
    public async Task The_lowest_of_the_newest_approved_prices_is_shown_with_the_store()
    {
        var product = await AddProductAsync("Švyturys Ekstra", 500);
        var a = await AddStoreAsync("Parduotuvė A");
        var b = await AddStoreAsync("Parduotuvė B");
        var c = await AddStoreAsync("Parduotuvė C");
        await AddPriceAsync(a, product, 100, Now.AddDays(-5)); // superseded: must not count
        await AddPriceAsync(a, product, 180, Now.AddDays(-1));
        await AddPriceAsync(b, product, 150, Now.AddDays(-2));
        await AddPriceAsync(c, product, 120, Now.AddDays(-3));
        await AddPriceAsync(c, product, 50, Now.AddDays(-1), PriceStatus.Rejected); // wrong: ignored
        await AddPriceAsync(c, product, 10, Now.AddHours(-1), PriceStatus.Pending); // unconfirmed: ignored

        var item = Assert.Single(await SearchAsync("ekstra"));

        var lowest = item.LowestPrice!;
        Assert.Equal(120, lowest.PriceCents);
        Assert.Equal("Parduotuvė C", lowest.StoreName);
        Assert.Equal(c, lowest.StoreId);
        Assert.Equal(Now.AddDays(-3), lowest.ObservedAt);
        Assert.False(lowest.IsStale);
    }

    [Fact]
    public async Task Staleness_follows_the_seven_day_rule_and_a_product_without_prices_has_none()
    {
        var store = await AddStoreAsync("Parduotuvė A");
        var old = await AddProductAsync("Senas alus", 500);
        await AddPriceAsync(store, old, 100, Now.AddDays(-8));
        await AddProductAsync("Naujas alus", 500); // no prices

        var response = await _client.GetAsync("/api/v1/products/search?q=alus");
        var json = await response.Content.ReadAsStringAsync();
        var items = (await response.Content.ReadFromJsonAsync<ProductSearchResponse>())!.Items;

        Assert.True(items.Single(i => i.Name == "Senas alus").LowestPrice!.IsStale);
        Assert.Null(items.Single(i => i.Name == "Naujas alus").LowestPrice);
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(json, "lowestPrice")); // omitted when absent
    }

    [Fact]
    public async Task Searching_takes_two_statements_however_many_results()
    {
        var store = await AddStoreAsync("Parduotuvė A");
        for (var i = 0; i < 12; i++)
        {
            var product = await AddProductAsync($"Alus {i:00}", 500);
            await AddPriceAsync(store, product, 100 + i, Now.AddDays(-1));
        }

        var counter = new CommandCounter();
        await using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseAlusekisSqlite(_database.ConnectionString)
            .AddInterceptors(counter)
            .Options);

        var result = await ProductSearch.SearchAsync(db, Now, "alus", CancellationToken.None);

        Assert.Equal(12, result.Items.Count);
        Assert.Equal(2, counter.Count); // products + their prices, no query per product
    }

    // ---------- helpers ----------

    private async Task<IReadOnlyList<ProductSearchItemDto>> SearchAsync(string query)
    {
        var response = await _client.GetAsync($"/api/v1/products/search?q={Uri.EscapeDataString(query)}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<ProductSearchResponse>())!.Items;
    }

    private static async Task AssertValidationErrorAsync(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(ErrorCodes.ValidationFailed, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }

    private async Task<long> AddProductAsync(string name, int volumeMl)
    {
        await using var db = _database.CreateContext();
        var product = new Product
        {
            Name = name,
            // The same function the server uses when it creates a product.
            NormalizedName = TextNormalizer.NormalizeName(name),
            VolumeMl = volumeMl,
            CreatedAt = Now,
        };
        db.Products.Add(product);
        await db.SaveChangesAsync();
        return product.Id;
    }

    private async Task<long> AddStoreAsync(string name)
    {
        await using var db = _database.CreateContext();
        if (_cityId is null)
        {
            var city = new City { Name = "Vilnius", NormalizedName = "vilnius" };
            db.Cities.Add(city);
            await db.SaveChangesAsync();
            _cityId = city.Id;
        }

        var store = new Store { CityId = _cityId.Value, Name = name, Address = "Gatvė 1", CreatedAt = Now };
        db.Stores.Add(store);
        await db.SaveChangesAsync();
        return store.Id;
    }

    private async Task AddPriceAsync(
        long storeId, long productId, int cents, DateTime observedAt, PriceStatus status = PriceStatus.Approved)
    {
        await using var db = _database.CreateContext();
        db.PriceEntries.Add(new PriceEntry
        {
            StoreId = storeId,
            ProductId = productId,
            PriceCents = cents,
            Status = status,
            ObservedAt = observedAt,
            CreatedAt = observedAt,
        });
        await db.SaveChangesAsync();
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
