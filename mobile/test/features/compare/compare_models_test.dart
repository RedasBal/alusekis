import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/compare/compare_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _offerJson(int id, int storeId, String store, int cents) => {
      'priceEntryId': id,
      'storeId': storeId,
      'storeName': store,
      'storeAddress': 'Gatvė $storeId',
      'priceCents': cents,
      'observedAt': '2026-11-20T10:30:00Z',
      'isStale': false,
    };

StoreOffer _offer(int cents) => StoreOffer.fromJson(_offerJson(1, 1, 'A', cents));

void main() {
  group('ProductComparison.fromJson', () {
    test('reads the product, the offers in server order and the counts', () {
      final comparison = ProductComparison.fromJson({
        'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
        'items': [_offerJson(1, 4, 'Lidl', 139), _offerJson(2, 1, 'Maxima XX', 149)],
        'storeCount': 2,
        'singleStore': false,
      });

      expect(comparison.product.id, 7);
      expect(comparison.product.name, 'Švyturys Ekstra');
      expect(comparison.product.brand, 'Švyturys');
      expect(comparison.product.volumeMl, 500);
      expect(comparison.offers.map((o) => o.storeName), ['Lidl', 'Maxima XX']);
      expect(comparison.offers.first.priceCents, 139);
      expect(comparison.offers.first.observedAt, DateTime.utc(2026, 11, 20, 10, 30));
      expect(comparison.offers.first.observedAt.isUtc, isTrue);
      expect(comparison.storeCount, 2);
      expect(comparison.singleStore, isFalse);
    });

    test('a missing brand is allowed', () {
      final comparison = ProductComparison.fromJson({
        'product': {'id': 1, 'name': 'Alus', 'volumeMl': 330},
        'items': <Object>[],
        'storeCount': 0,
        'singleStore': false,
      });

      expect(comparison.product.brand, isNull);
      expect(comparison.offers, isEmpty);
    });

    test('the sort values are the ones the server expects', () {
      expect(PriceSort.asc.apiValue, 'asc');
      expect(PriceSort.desc.apiValue, 'desc');
    });
  });

  group('price difference in whole cents', () {
    test('the cheapest price is found whatever the order', () {
      expect(cheapestPriceCents([_offer(149), _offer(139), _offer(200)]), 139);
      expect(cheapestPriceCents([_offer(200), _offer(149), _offer(139)]), 139);
      expect(cheapestPriceCents([_offer(5)]), 5);
      expect(cheapestPriceCents([]), isNull);
    });

    test('the difference is an exact integer, not a rounded double', () {
      // 1,49 - 1,39 would be 0.10000000000000009 as doubles; as cents it is exactly 10.
      expect(differenceFromCheapestCents(_offer(149), 139), 10);
      expect(differenceFromCheapestCents(_offer(139), 139), 0);
      expect(differenceFromCheapestCents(_offer(50000), 1), 49999);
      expect(differenceFromCheapestCents(_offer(1), 1), 0);
      expect(differenceFromCheapestCents(_offer(149), 139), isA<int>());
    });

    test('it is shown as a sum with a plus sign and a comma', () {
      expect(formatPriceDifference(10), '+${formatPrice(10)}');
      expect(formatPriceDifference(10), startsWith('+0,10'));
      expect(formatPriceDifference(1), startsWith('+0,01'));
      expect(formatPriceDifference(150), startsWith('+1,50'));
      expect(formatPriceDifference(0), startsWith('+0,00'));
    });

    test('a negative difference is a programming error', () {
      expect(() => formatPriceDifference(-1), throwsArgumentError);
    });
  });
}
