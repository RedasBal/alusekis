using System.Text.Json.Serialization;
using Alusekis.Api.Api;
using Alusekis.Api.Data;
using Alusekis.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace Alusekis.Api.Stores;

public sealed record CityDto(long Id, string Name);

public sealed record CityListResponse(IReadOnlyList<CityDto> Items);

public sealed record StoreDto(
    long Id,
    string Name,
    string Address,
    double? Latitude,
    double? Longitude,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] double? DistanceKm,
    CityDto City);

public sealed record StoreListResponse(IReadOnlyList<StoreDto> Items);

/// <summary>Public (guest) read endpoints: <c>/api/v1/cities</c> and <c>/api/v1/stores</c>.</summary>
public static class StoreEndpoints
{
    public const int MinRadiusKm = 1;
    public const int MaxRadiusKm = 50;

    /// <summary>Upper bound of one response; a 50 km radius around a city centre stays well below it.</summary>
    public const int MaxResults = 200;

    public static RouteGroupBuilder MapStores(this RouteGroupBuilder v1)
    {
        v1.MapGet("/cities", GetCities);
        v1.MapGet("/stores", GetStores);
        return v1;
    }

    private static async Task<IResult> GetCities(AppDbContext db, CancellationToken ct)
    {
        var cities = await db.Cities.AsNoTracking()
            .OrderBy(c => c.NormalizedName)
            .Select(c => new CityDto(c.Id, c.Name))
            .ToListAsync(ct);

        return Results.Ok(new CityListResponse(cities));
    }

    /// <summary>
    /// Either <c>lat</c> + <c>lng</c> + <c>radiusKm</c> (nearby search, sorted by distance) or
    /// <c>cityId</c> (all stores of the city, sorted by name). The coordinates are used for this
    /// one query only: they are neither stored nor logged.
    /// </summary>
    private static async Task<IResult> GetStores(
        HttpContext http,
        AppDbContext db,
        double? lat,
        double? lng,
        int? radiusKm,
        long? cityId,
        CancellationToken ct)
    {
        var anyGps = lat is not null || lng is not null || radiusKm is not null;

        if (cityId is not null && anyGps)
        {
            return Invalid(http, "Use either lat, lng and radiusKm, or cityId, not both.");
        }

        if (cityId is not null)
        {
            return Results.Ok(await ByCityAsync(db, cityId.Value, ct));
        }

        if (!anyGps)
        {
            return Invalid(http, "Provide lat, lng and radiusKm, or cityId.");
        }

        if (lat is null || lng is null || radiusKm is null)
        {
            return Invalid(http, "lat, lng and radiusKm must be provided together.");
        }

        if (!double.IsFinite(lat.Value) || lat.Value is < -90 or > 90)
        {
            return Invalid(http, "lat must be between -90 and 90.");
        }

        if (!double.IsFinite(lng.Value) || lng.Value is < -180 or > 180)
        {
            return Invalid(http, "lng must be between -180 and 180.");
        }

        if (radiusKm.Value is < MinRadiusKm or > MaxRadiusKm)
        {
            return Invalid(http, $"radiusKm must be between {MinRadiusKm} and {MaxRadiusKm}.");
        }

        return Results.Ok(await NearbyAsync(db, lat.Value, lng.Value, radiusKm.Value, ct));
    }

    private static async Task<StoreListResponse> ByCityAsync(AppDbContext db, long cityId, CancellationToken ct)
    {
        // An unknown city is simply a city without stores: empty list, not an error.
        var stores = await db.Stores.AsNoTracking()
            .Where(s => s.CityId == cityId)
            .Include(s => s.City)
            .ToListAsync(ct);

        var items = stores
            .OrderBy(s => TextNormalizer.NormalizeName(s.Name), StringComparer.Ordinal)
            .ThenBy(s => s.Address, StringComparer.Ordinal)
            .Take(MaxResults)
            .Select(s => ToDto(s, distanceKm: null))
            .ToList();

        return new StoreListResponse(items);
    }

    private static async Task<StoreListResponse> NearbyAsync(
        AppDbContext db, double lat, double lng, int radiusKm, CancellationToken ct)
    {
        var box = GeoMath.BoundingBoxAround(lat, lng, radiusKm);

        var query = db.Stores.AsNoTracking()
            .Where(s => s.Latitude != null && s.Longitude != null
                && s.Latitude >= box.MinLat && s.Latitude <= box.MaxLat);
        if (box.MinLng is { } minLng && box.MaxLng is { } maxLng)
        {
            query = query.Where(s => s.Longitude >= minLng && s.Longitude <= maxLng);
        }

        var candidates = await query.Include(s => s.City).ToListAsync(ct);

        var items = candidates
            .Select(s => (Store: s, Km: GeoMath.HaversineKm(lat, lng, s.Latitude!.Value, s.Longitude!.Value)))
            .Where(x => x.Km <= radiusKm)
            .OrderBy(x => x.Km)
            .ThenBy(x => TextNormalizer.NormalizeName(x.Store.Name), StringComparer.Ordinal)
            .Take(MaxResults)
            .Select(x => ToDto(x.Store, Math.Round(x.Km, 2)))
            .ToList();

        return new StoreListResponse(items);
    }

    private static StoreDto ToDto(Store store, double? distanceKm) => new(
        store.Id,
        store.Name,
        store.Address,
        store.Latitude,
        store.Longitude,
        distanceKm,
        new CityDto(store.City.Id, store.City.Name));

    private static IResult Invalid(HttpContext http, string message) =>
        ErrorResponses.Result(http, StatusCodes.Status422UnprocessableEntity, ErrorCodes.ValidationFailed, message);
}
