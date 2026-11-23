using System.Net;
using System.Net.Http.Json;
using Alusekis.Api.Api;
using Alusekis.Api.Seeding;
using Alusekis.Api.Stores;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Tests;

public sealed class StoreTests : IDisposable
{
    // Vilnius city centre; the seeded Vilnius stores are all within ~7 km of it.
    private const string CentreLat = "54.6872";
    private const string CentreLng = "25.2797";

    private readonly TestDatabase _database = new();
    private readonly AuthApiFactory _factory;
    private readonly HttpClient _client;

    public StoreTests()
    {
        using (var db = _database.CreateContext())
        {
            new DataSeeder(db).SeedAsync().GetAwaiter().GetResult();
        }

        _factory = new AuthApiFactory(_database.ConnectionString, new FakeClock(), new CapturingEmailSender());
        _client = _factory.CreateClient();
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        _database.Dispose();
    }

    [Fact]
    public async Task Gps_search_returns_stores_in_radius_nearest_first()
    {
        var response = await _client.GetAsync($"/api/v1/stores?lat={CentreLat}&lng={CentreLng}&radiusKm=10");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var items = (await response.Content.ReadFromJsonAsync<StoreListResponse>())!.Items;
        Assert.Equal(5, items.Count);
        Assert.All(items, s =>
        {
            Assert.Equal("Vilnius", s.City.Name);
            Assert.InRange(s.DistanceKm!.Value, 0, 10);
            Assert.NotNull(s.Latitude);
            Assert.NotNull(s.Longitude);
        });
        Assert.Equal(items.OrderBy(s => s.DistanceKm), items); // sorted by distance
    }

    [Fact]
    public async Task Gps_search_with_a_small_radius_finds_only_the_store_next_to_you()
    {
        // The Ozo g. 25 store's own coordinates.
        var items = (await GetStores("lat=54.7117&lng=25.2827&radiusKm=1")).Items;

        var store = Assert.Single(items);
        Assert.Equal("Rimi Hyper", store.Name);
        Assert.True(store.DistanceKm < 0.1);
    }

    [Fact]
    public async Task Search_with_no_stores_nearby_returns_an_empty_list_not_an_error()
    {
        var response = await _client.GetAsync("/api/v1/stores?lat=0&lng=0&radiusKm=50");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty((await response.Content.ReadFromJsonAsync<StoreListResponse>())!.Items);
    }

    [Fact]
    public async Task City_search_lists_the_cities_stores_by_name_without_distance()
    {
        var cities = (await _client.GetFromJsonAsync<CityListResponse>("/api/v1/cities"))!.Items;
        var kaunas = cities.Single(c => c.Name == "Kaunas");

        var response = await _client.GetAsync($"/api/v1/stores?cityId={kaunas.Id}");
        var json = await response.Content.ReadAsStringAsync();
        var items = (await response.Content.ReadFromJsonAsync<StoreListResponse>())!.Items;

        Assert.Equal(4, items.Count);
        Assert.All(items, s => Assert.Equal("Kaunas", s.City.Name));
        Assert.Equal(["Iki", "Lidl", "Maxima XXX", "Rimi"], items.Select(s => s.Name));
        Assert.DoesNotContain("distanceKm", json);
    }

    [Fact]
    public async Task Unknown_city_gives_an_empty_list()
    {
        Assert.Empty((await GetStores("cityId=999999")).Items);
    }

    [Fact]
    public async Task Cities_are_listed_by_name()
    {
        var cities = (await _client.GetFromJsonAsync<CityListResponse>("/api/v1/cities"))!.Items;

        Assert.Equal(["Kaunas", "Klaipėda", "Vilnius"], cities.Select(c => c.Name));
    }

    [Theory]
    [InlineData(0, HttpStatusCode.UnprocessableEntity)]
    [InlineData(1, HttpStatusCode.OK)]
    [InlineData(50, HttpStatusCode.OK)]
    [InlineData(51, HttpStatusCode.UnprocessableEntity)]
    public async Task Radius_is_limited_to_1_through_50_km(int radiusKm, HttpStatusCode expected)
    {
        var response = await _client.GetAsync($"/api/v1/stores?lat={CentreLat}&lng={CentreLng}&radiusKm={radiusKm}");

        Assert.Equal(expected, response.StatusCode);
        if (expected != HttpStatusCode.OK)
        {
            await AssertErrorDto(response, ErrorCodes.ValidationFailed);
        }
    }

    [Theory]
    [InlineData("91", "25", HttpStatusCode.UnprocessableEntity)]
    [InlineData("-91", "25", HttpStatusCode.UnprocessableEntity)]
    [InlineData("54", "181", HttpStatusCode.UnprocessableEntity)]
    [InlineData("54", "-181", HttpStatusCode.UnprocessableEntity)]
    [InlineData("NaN", "25", HttpStatusCode.UnprocessableEntity)]
    [InlineData("90", "180", HttpStatusCode.OK)]
    [InlineData("-90", "-180", HttpStatusCode.OK)]
    [InlineData("abc", "25", HttpStatusCode.BadRequest)]
    public async Task Invalid_coordinates_are_rejected_with_an_error_dto(string lat, string lng, HttpStatusCode expected)
    {
        var response = await _client.GetAsync($"/api/v1/stores?lat={lat}&lng={lng}&radiusKm=10");

        Assert.Equal(expected, response.StatusCode);
        if (expected != HttpStatusCode.OK)
        {
            Assert.False(string.IsNullOrEmpty((await response.Content.ReadFromJsonAsync<ErrorDto>())!.RequestId));
        }
    }

    [Theory]
    [InlineData("")]
    [InlineData("lat=54.7")]
    [InlineData("lat=54.7&lng=25.2")]
    [InlineData("cityId=1&lat=54.7&lng=25.2&radiusKm=5")]
    public async Task Missing_or_conflicting_parameters_are_rejected(string query)
    {
        var response = await _client.GetAsync($"/api/v1/stores?{query}");

        Assert.Equal(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        await AssertErrorDto(response, ErrorCodes.ValidationFailed);
    }

    [Fact]
    public void Haversine_gives_the_real_distance_between_Vilnius_and_Kaunas()
    {
        var km = GeoMath.HaversineKm(54.6872, 25.2797, 54.8985, 23.9036);

        Assert.InRange(km, 90, 100);
        Assert.Equal(0, GeoMath.HaversineKm(54.6, 25.2, 54.6, 25.2));
    }

    [Fact]
    public async Task Seed_gives_every_store_coordinates_in_at_least_two_cities_and_stays_idempotent()
    {
        await using (var db = _database.CreateContext())
        {
            var second = await new DataSeeder(db).SeedAsync();
            Assert.Equal(0, second.Total);
        }

        await using var verify = _database.CreateContext();
        var stores = await verify.Stores.AsNoTracking().ToListAsync();
        Assert.Equal(12, stores.Count);
        Assert.All(stores, s =>
        {
            Assert.NotNull(s.Latitude);
            Assert.NotNull(s.Longitude);
        });
        Assert.True(stores.Select(s => s.CityId).Distinct().Count() >= 2);
    }

    private async Task<StoreListResponse> GetStores(string query) =>
        (await _client.GetFromJsonAsync<StoreListResponse>($"/api/v1/stores?{query}"))!;

    private static async Task AssertErrorDto(HttpResponseMessage response, string code)
    {
        var error = (await response.Content.ReadFromJsonAsync<ErrorDto>())!;
        Assert.Equal(code, error.Code);
        Assert.False(string.IsNullOrEmpty(error.RequestId));
    }
}
