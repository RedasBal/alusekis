import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'open_street_map_provider.dart';
import 'store_models.dart';

/// Draws stores on a map. The rest of the app depends only on this interface,
/// so the map provider can be swapped (e.g. for Google Maps) in one place.
abstract interface class MapProvider {
  /// [origin] (the user's position) is shown when given. Tapping a store marker
  /// calls [onStoreTap]. Stores without coordinates are not drawn.
  Widget build(
    BuildContext context, {
    required List<StoreItem> stores,
    required void Function(StoreItem store) onStoreTap,
    GeoPoint? origin,
  });
}

final mapProviderProvider =
    Provider<MapProvider>((ref) => const OpenStreetMapProvider());
