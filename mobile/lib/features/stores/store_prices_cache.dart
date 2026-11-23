import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_preferences.dart';
import '../../core/utils/date_format.dart';
import 'store_prices_models.dart';

/// The last successful answer for one store, kept on the device (FR-16).
class PricesSnapshot {
  const PricesSnapshot({
    required this.store,
    required this.items,
    required this.total,
    required this.syncedAt,
  });

  factory PricesSnapshot.fromJson(Map<String, dynamic> json) => PricesSnapshot(
        store: StoreSummary.fromJson(json['store'] as Map<String, dynamic>),
        items: [
          for (final item in json['items'] as List<dynamic>)
            StorePrice.fromJson(item as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
        syncedAt: parseServerDateTime(json['syncedAt'] as String),
      );

  final StoreSummary store;

  /// The pages the user had loaded when the snapshot was taken.
  final List<StorePrice> items;
  final int total;

  /// When the server last answered successfully (UTC).
  final DateTime syncedAt;

  Map<String, dynamic> toJson() => {
        'store': store.toJson(),
        'items': [for (final item in items) item.toJson()],
        'total': total,
        'syncedAt': toServerDateTime(syncedAt),
      };
}

/// Per-store price snapshots in the app preferences. Only the newest snapshot
/// of each store is kept; an unreadable one is discarded.
class StorePricesCache {
  StorePricesCache(this._prefs);

  final AppPreferences _prefs;

  static String _key(int storeId) => 'store_prices_$storeId';

  PricesSnapshot? read(int storeId) {
    final raw = _prefs.getCachedJson(_key(storeId));
    if (raw == null) {
      return null;
    }
    try {
      return PricesSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _prefs.removeCachedJson(_key(storeId)).ignore();
      return null;
    }
  }

  Future<void> write(int storeId, PricesSnapshot snapshot) =>
      _prefs.setCachedJson(_key(storeId), jsonEncode(snapshot.toJson()));
}

final storePricesCacheProvider = Provider<StorePricesCache>(
  (ref) => StorePricesCache(ref.watch(appPreferencesProvider)),
);
