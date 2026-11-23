import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'store_models.dart';

enum LocationFailure {
  /// The user declined the permission this time.
  denied,

  /// "Don't ask again": only the phone settings can change it.
  deniedForever,

  /// Location is switched off on the phone.
  serviceDisabled,

  /// Anything else (no fix in time, platform error).
  unavailable,
}

class LocationResult {
  const LocationResult.success(GeoPoint this.point) : failure = null;

  const LocationResult.failure(LocationFailure this.failure) : point = null;

  final GeoPoint? point;
  final LocationFailure? failure;
}

/// Gets the current position. The only place that touches the location
/// plugin, so tests (and other platforms) can substitute it.
abstract interface class LocationService {
  /// Asks for the permission if needed, then reads the position once.
  /// Call it only in response to the user's tap.
  Future<LocationResult> requestCurrentPosition();

  Future<void> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationResult> requestCurrentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(LocationFailure.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failure(LocationFailure.denied);
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failure(LocationFailure.serviceDisabled);
      }

      // Approximate accuracy is enough to find stores nearby.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult.success(
        GeoPoint(position.latitude, position.longitude),
      );
    } catch (error) {
      // Never log the position itself; the error type is enough.
      debugPrint('Location unavailable: ${error.runtimeType}');
      return const LocationResult.failure(LocationFailure.unavailable);
    }
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}

final locationServiceProvider =
    Provider<LocationService>((ref) => const GeolocatorLocationService());
