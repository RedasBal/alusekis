import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';

/// Order of the stores in a comparison. The server does the sorting.
enum PriceSort {
  /// Cheapest first (the server default).
  asc,

  /// Dearest first.
  desc;

  String get apiValue => name;
}

/// The product being compared. A product is its name **and** its volume: the
/// same name in another volume is a different product with its own id.
class ComparedProduct {
  const ComparedProduct({
    required this.id,
    required this.name,
    required this.volumeMl,
    this.brand,
  });

  factory ComparedProduct.fromJson(Map<String, dynamic> json) => ComparedProduct(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        brand: json['brand'] as String?,
        volumeMl: (json['volumeMl'] as num).toInt(),
      );

  final int id;
  final String name;
  final String? brand;
  final int volumeMl;
}

/// One store's newest valid price of the product.
class StoreOffer {
  const StoreOffer({
    required this.priceEntryId,
    required this.storeId,
    required this.storeName,
    required this.storeAddress,
    required this.priceCents,
    required this.observedAt,
    required this.isStale,
  });

  factory StoreOffer.fromJson(Map<String, dynamic> json) => StoreOffer(
        priceEntryId: (json['priceEntryId'] as num).toInt(),
        storeId: (json['storeId'] as num).toInt(),
        storeName: json['storeName'] as String,
        storeAddress: json['storeAddress'] as String,
        priceCents: (json['priceCents'] as num).toInt(),
        observedAt: parseServerDateTime(json['observedAt'] as String),
        isStale: json['isStale'] as bool,
      );

  final int priceEntryId;
  final int storeId;
  final String storeName;
  final String storeAddress;

  /// Whole euro cents; prices are never floating point.
  final int priceCents;

  /// When the price was seen in the store (UTC).
  final DateTime observedAt;

  /// Older than 7 days by the server's clock.
  final bool isStale;
}

class ProductComparison {
  const ProductComparison({
    required this.product,
    required this.offers,
    required this.storeCount,
    required this.singleStore,
  });

  factory ProductComparison.fromJson(Map<String, dynamic> json) => ProductComparison(
        product: ComparedProduct.fromJson(json['product'] as Map<String, dynamic>),
        offers: [
          for (final item in json['items'] as List<dynamic>)
            StoreOffer.fromJson(item as Map<String, dynamic>),
        ],
        storeCount: (json['storeCount'] as num).toInt(),
        singleStore: json['singleStore'] as bool,
      );

  final ComparedProduct product;

  /// In the order the server sorted them.
  final List<StoreOffer> offers;
  final int storeCount;

  /// Only one store has a price, so there is nothing to compare it with.
  final bool singleStore;
}

/// The lowest price among [offers] in cents, whatever their order; null if none.
int? cheapestPriceCents(List<StoreOffer> offers) {
  if (offers.isEmpty) {
    return null;
  }
  return offers.map((o) => o.priceCents).reduce((a, b) => a < b ? a : b);
}

/// How much dearer [offer] is than the cheapest offer, in whole cents (0 for
/// the cheapest itself). Integer arithmetic only.
int differenceFromCheapestCents(StoreOffer offer, int cheapestCents) =>
    offer.priceCents - cheapestCents;

/// "+0,20 €" for a difference in cents (never negative).
String formatPriceDifference(int cents) {
  if (cents < 0) {
    throw ArgumentError.value(cents, 'cents', 'must not be negative');
  }
  return '+${formatPrice(cents)}';
}
