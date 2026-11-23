/// A point on Earth (WGS 84). Kept independent of any map package so the map
/// provider can be replaced.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class City {
  const City({required this.id, required this.name});

  factory City.fromJson(Map<String, dynamic> json) => City(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
      );

  final int id;
  final String name;
}

class StoreItem {
  const StoreItem({
    required this.id,
    required this.name,
    required this.address,
    required this.cityName,
    this.latitude,
    this.longitude,
    this.distanceKm,
  });

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    final city = json['city'] as Map<String, dynamic>;
    return StoreItem(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      address: json['address'] as String,
      cityName: city['name'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    );
  }

  final int id;
  final String name;
  final String address;
  final String cityName;
  final double? latitude;
  final double? longitude;

  /// Only present for searches by position.
  final double? distanceKm;

  bool get hasLocation => latitude != null && longitude != null;
}

/// "3,7 km" (Lithuanian decimal comma); under a kilometre shown in metres.
String formatDistance(double km) {
  if (km < 1) {
    return '${(km * 1000).round()} m';
  }
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
