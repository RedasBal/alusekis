import '../../core/utils/date_format.dart';

/// The cheapest of a product's newest approved prices.
class ProductLowestPrice {
  const ProductLowestPrice({
    required this.priceCents,
    required this.storeId,
    required this.storeName,
    required this.observedAt,
    required this.isStale,
  });

  factory ProductLowestPrice.fromJson(Map<String, dynamic> json) => ProductLowestPrice(
        priceCents: (json['priceCents'] as num).toInt(),
        storeId: (json['storeId'] as num).toInt(),
        storeName: json['storeName'] as String,
        observedAt: parseServerDateTime(json['observedAt'] as String),
        isStale: json['isStale'] as bool,
      );

  /// Whole euro cents.
  final int priceCents;
  final int storeId;
  final String storeName;
  final DateTime observedAt;

  /// Older than 7 days by the server's clock.
  final bool isStale;
}

class ProductSearchItem {
  const ProductSearchItem({
    required this.id,
    required this.name,
    required this.volumeMl,
    this.brand,
    this.lowestPrice,
  });

  factory ProductSearchItem.fromJson(Map<String, dynamic> json) {
    final price = json['lowestPrice'];
    return ProductSearchItem(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      brand: json['brand'] as String?,
      volumeMl: (json['volumeMl'] as num).toInt(),
      lowestPrice: price == null
          ? null
          : ProductLowestPrice.fromJson(price as Map<String, dynamic>),
    );
  }

  final int id;
  final String name;
  final String? brand;
  final int volumeMl;

  /// Absent when no store has a confirmed price for the product.
  final ProductLowestPrice? lowestPrice;
}
