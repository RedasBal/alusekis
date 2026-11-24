import '../../core/utils/date_format.dart';

/// Server threshold for the "stale" flag (FR-17).
const Duration staleAfter = Duration(days: 7);

class StoreSummary {
  const StoreSummary({required this.id, required this.name, required this.address});

  factory StoreSummary.fromJson(Map<String, dynamic> json) => StoreSummary(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        address: json['address'] as String,
      );

  final int id;
  final String name;
  final String address;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address};
}

/// The latest valid price of one product in one store.
class StorePrice {
  const StorePrice({
    required this.priceEntryId,
    required this.productId,
    required this.productName,
    required this.volumeMl,
    required this.priceCents,
    required this.observedAt,
    required this.isStale,
  });

  factory StorePrice.fromJson(Map<String, dynamic> json) => StorePrice(
        priceEntryId: (json['priceEntryId'] as num).toInt(),
        productId: (json['productId'] as num).toInt(),
        productName: json['productName'] as String,
        volumeMl: (json['volumeMl'] as num).toInt(),
        priceCents: (json['priceCents'] as num).toInt(),
        observedAt: parseServerDateTime(json['observedAt'] as String),
        isStale: json['isStale'] as bool,
      );

  final int priceEntryId;
  final int productId;
  final String productName;
  final int volumeMl;

  /// Whole euro cents.
  final int priceCents;

  /// When the price was seen in the store (UTC).
  final DateTime observedAt;

  /// The server flagged the price as older than 7 days when it answered.
  final bool isStale;

  StorePrice copyWith({bool? isStale}) => StorePrice(
        priceEntryId: priceEntryId,
        productId: productId,
        productName: productName,
        volumeMl: volumeMl,
        priceCents: priceCents,
        observedAt: observedAt,
        isStale: isStale ?? this.isStale,
      );

  Map<String, dynamic> toJson() => {
        'priceEntryId': priceEntryId,
        'productId': productId,
        'productName': productName,
        'volumeMl': volumeMl,
        'priceCents': priceCents,
        'observedAt': toServerDateTime(observedAt),
        'isStale': isStale,
      };
}

/// One page of `GET /stores/{id}/prices`.
class StorePricesPage {
  const StorePricesPage({
    required this.store,
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory StorePricesPage.fromJson(Map<String, dynamic> json) => StorePricesPage(
        store: StoreSummary.fromJson(json['store'] as Map<String, dynamic>),
        items: [
          for (final item in json['items'] as List<dynamic>)
            StorePrice.fromJson(item as Map<String, dynamic>),
        ],
        total: (json['total'] as num).toInt(),
        page: (json['page'] as num).toInt(),
        pageSize: (json['pageSize'] as num).toInt(),
      );

  final StoreSummary store;
  final List<StorePrice> items;
  final int total;
  final int page;
  final int pageSize;
}

/// While offline the server cannot re-evaluate staleness, so a price counts as
/// stale if the server said so or if it is older than 7 days by the device
/// clock now. Never the other way round: a stale price does not become fresh.
List<StorePrice> markStaleByDeviceClock(List<StorePrice> items, DateTime nowUtc) => [
      for (final item in items)
        item.isStale || nowUtc.difference(item.observedAt) > staleAfter
            ? item.copyWith(isStale: true)
            : item,
    ];
