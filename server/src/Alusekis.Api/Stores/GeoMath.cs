namespace Alusekis.Api.Stores;

/// <summary>Distance helpers. SQLite has no geo functions, so the search narrows with a
/// bounding box in SQL and then measures exactly in memory.</summary>
public static class GeoMath
{
    private const double EarthRadiusKm = 6371.0088;
    private const double KmPerDegreeOfLatitude = 111.32;

    /// <summary>Great-circle distance between two WGS 84 points, in kilometres (Haversine).</summary>
    public static double HaversineKm(double lat1, double lng1, double lat2, double lng2)
    {
        var dLat = ToRadians(lat2 - lat1);
        var dLng = ToRadians(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
            + Math.Cos(ToRadians(lat1)) * Math.Cos(ToRadians(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * EarthRadiusKm * Math.Asin(Math.Min(1, Math.Sqrt(a)));
    }

    /// <summary>
    /// A rectangle that contains every point within <paramref name="radiusKm"/> of the centre
    /// (it may contain a bit more; the exact distance is checked afterwards). A longitude range
    /// that would cross the antimeridian or a pole is dropped (null) instead of being wrapped.
    /// </summary>
    public static BoundingBox BoundingBoxAround(double lat, double lng, double radiusKm)
    {
        var dLat = radiusKm / KmPerDegreeOfLatitude;
        var minLat = Math.Max(-90, lat - dLat);
        var maxLat = Math.Min(90, lat + dLat);

        double? minLng = null;
        double? maxLng = null;
        var cos = Math.Cos(ToRadians(lat));
        if (cos > 1e-6)
        {
            var dLng = radiusKm / (KmPerDegreeOfLatitude * cos);
            if (lng - dLng >= -180 && lng + dLng <= 180)
            {
                minLng = lng - dLng;
                maxLng = lng + dLng;
            }
        }

        return new BoundingBox(minLat, maxLat, minLng, maxLng);
    }

    private static double ToRadians(double degrees) => degrees * Math.PI / 180;
}

public readonly record struct BoundingBox(double MinLat, double MaxLat, double? MinLng, double? MaxLng);
