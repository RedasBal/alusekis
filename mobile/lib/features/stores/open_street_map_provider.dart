import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import 'map_provider.dart';
import 'store_models.dart';

/// [MapProvider] backed by flutter_map and OpenStreetMap tiles (no API key).
class OpenStreetMapProvider implements MapProvider {
  const OpenStreetMapProvider();

  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Identifies the app to the tile server, as its usage policy asks.
  static const _userAgentPackage = 'lt.vilniustech.alusekis';

  @override
  Widget build(
    BuildContext context, {
    required List<StoreItem> stores,
    required void Function(StoreItem store) onStoreTap,
    GeoPoint? origin,
  }) {
    final located = stores.where((s) => s.hasLocation).toList();
    final points = [
      for (final s in located) LatLng(s.latitude!, s.longitude!),
      if (origin != null) LatLng(origin.latitude, origin.longitude),
    ];

    if (points.isEmpty) {
      return const Center(child: Text('Šių parduotuvių žemėlapyje parodyti negalima.'));
    }

    return FlutterMap(
      // A new result set starts a new camera (the fit is only applied at start).
      key: ValueKey(
        Object.hashAll([
          for (final s in located) s.id,
          origin?.latitude,
          origin?.longitude,
        ]),
      ),
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(64),
          maxZoom: 15,
        ),
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: _userAgentPackage,
        ),
        MarkerLayer(
          markers: [
            for (final s in located)
              Marker(
                point: LatLng(s.latitude!, s.longitude!),
                width: minTapTarget,
                height: minTapTarget,
                child: _StoreMarker(store: s, onTap: () => onStoreTap(s)),
              ),
            if (origin != null)
              Marker(
                point: LatLng(origin.latitude, origin.longitude),
                width: minTapTarget,
                height: minTapTarget,
                child: const _OriginMarker(),
              ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('© OpenStreetMap')),
      ],
    );
  }
}

/// A store pin: a circle with a shop icon, so it is recognisable by shape and
/// symbol and not by colour. 48×48 tap area.
class _StoreMarker extends StatelessWidget {
  const _StoreMarker({required this.store, required this.onTap});

  final StoreItem store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${store.name}, ${store.address}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.onPrimaryContainer, width: 2),
            ),
            child: Icon(Icons.storefront, color: scheme.onPrimaryContainer),
          ),
        ),
      ),
    );
  }
}

/// The user's own position: a different shape (rounded square) and icon.
class _OriginMarker extends StatelessWidget {
  const _OriginMarker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Jūsų vieta',
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.onTertiaryContainer, width: 2),
          ),
          child: Icon(Icons.my_location, color: scheme.onTertiaryContainer),
        ),
      ),
    );
  }
}
