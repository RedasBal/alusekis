import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/features/stores/store_prices_cache.dart';
import 'package:alusekis/features/stores/store_prices_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StorePrice _price(int id, {DateTime? observedAt, bool stale = false}) => StorePrice(
      priceEntryId: id,
      productId: id,
      productName: 'Produktas $id',
      volumeMl: 500,
      priceCents: 100 + id,
      observedAt: observedAt ?? DateTime.utc(2026, 11, 20, 10, 30),
      isStale: stale,
    );

PricesSnapshot _snapshot({List<StorePrice>? items, DateTime? syncedAt}) => PricesSnapshot(
      store: const StoreSummary(id: 1, name: 'Maxima XX', address: 'Ukmergės g. 282'),
      items: items ?? [_price(1), _price(2, stale: true)],
      total: 5,
      syncedAt: syncedAt ?? DateTime.utc(2026, 11, 21, 8, 15),
    );

Future<AppPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return AppPreferences(await SharedPreferences.getInstance());
}

void main() {
  group('StorePricesCache', () {
    test('returns nothing for a store that was never saved', () async {
      expect(StorePricesCache(await _prefs()).read(1), isNull);
    });

    test('gives back what was saved, including the sync time and stale flags',
        () async {
      final cache = StorePricesCache(await _prefs());

      await cache.write(1, _snapshot());
      final read = cache.read(1)!;

      expect(read.store.name, 'Maxima XX');
      expect(read.total, 5);
      expect(read.syncedAt, DateTime.utc(2026, 11, 21, 8, 15));
      expect(read.syncedAt.isUtc, isTrue);
      expect(read.items.map((i) => i.priceEntryId), [1, 2]);
      expect(read.items.map((i) => i.isStale), [false, true]);
      expect(read.items.first.priceCents, 101);
      expect(read.items.first.observedAt, DateTime.utc(2026, 11, 20, 10, 30));
    });

    test('keeps each store separate and only the newest answer per store',
        () async {
      final cache = StorePricesCache(await _prefs());

      await cache.write(1, _snapshot(items: [_price(1)]));
      await cache.write(2, _snapshot(items: [_price(7), _price(8)]));
      await cache.write(1, _snapshot(items: [_price(3)]));

      expect(cache.read(1)!.items.map((i) => i.priceEntryId), [3]);
      expect(cache.read(2)!.items.map((i) => i.priceEntryId), [7, 8]);
      expect(cache.read(3), isNull);
    });

    test('survives a restart (new preferences instance over the same storage)',
        () async {
      final first = await _prefs();
      await StorePricesCache(first).write(1, _snapshot());

      final reopened = AppPreferences(await SharedPreferences.getInstance());

      expect(StorePricesCache(reopened).read(1)!.total, 5);
    });

    test('an unreadable entry is discarded instead of crashing', () async {
      final prefs = await _prefs({'cache_store_prices_1': '{not json'});
      final cache = StorePricesCache(prefs);

      expect(cache.read(1), isNull);
      await Future<void>.delayed(Duration.zero); // the bad entry is removed
      expect(prefs.getCachedJson('store_prices_1'), isNull);
    });
  });

  group('markStaleByDeviceClock', () {
    final now = DateTime.utc(2026, 11, 23, 12);

    test('flags prices older than 7 days, not exactly 7 days', () {
      final marked = markStaleByDeviceClock(
        [
          _price(1, observedAt: now.subtract(const Duration(days: 8))),
          _price(2, observedAt: now.subtract(const Duration(days: 7))),
          _price(3, observedAt: now.subtract(const Duration(days: 6))),
        ],
        now,
      );

      expect(marked.map((p) => p.isStale), [true, false, false]);
    });

    test('a price the server called stale never becomes fresh', () {
      final marked = markStaleByDeviceClock(
        [_price(1, observedAt: now, stale: true)],
        now,
      );

      expect(marked.single.isStale, isTrue);
    });
  });
}
