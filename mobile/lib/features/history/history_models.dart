import '../../core/utils/date_format.dart';
import '../compare/compare_models.dart';

/// How far back the history goes. The server accepts exactly these values.
enum HistoryPeriod {
  week(7, '7 d.'),
  month(30, '30 d.'),
  quarter(90, '90 d.');

  const HistoryPeriod(this.days, this.label);

  final int days;

  /// Text on the period selector.
  final String label;

  /// Shown when the screen opens.
  static const HistoryPeriod defaultPeriod = HistoryPeriod.month;
}

class HistoryStore {
  const HistoryStore({required this.id, required this.name, required this.address});

  factory HistoryStore.fromJson(Map<String, dynamic> json) => HistoryStore(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        address: json['address'] as String,
      );

  final int id;
  final String name;
  final String address;
}

/// One recorded price. One entry on the server is one point here: nothing is
/// averaged, filled in between or merged.
class PricePoint {
  const PricePoint({
    required this.priceEntryId,
    required this.priceCents,
    required this.observedAt,
  });

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        priceEntryId: (json['priceEntryId'] as num).toInt(),
        priceCents: (json['priceCents'] as num).toInt(),
        observedAt: parseServerDateTime(json['observedAt'] as String),
      );

  final int priceEntryId;

  /// Whole euro cents.
  final int priceCents;

  /// When the price was seen in the store (UTC).
  final DateTime observedAt;
}

/// The recorded prices of one product in one store over [days] days.
class PriceHistory {
  const PriceHistory({
    required this.product,
    required this.store,
    required this.days,
    required this.from,
    required this.to,
    required this.points,
  });

  factory PriceHistory.fromJson(Map<String, dynamic> json) => PriceHistory(
        product: ComparedProduct.fromJson(json['product'] as Map<String, dynamic>),
        store: HistoryStore.fromJson(json['store'] as Map<String, dynamic>),
        days: (json['days'] as num).toInt(),
        from: parseServerDateTime(json['from'] as String),
        to: parseServerDateTime(json['to'] as String),
        points: [
          for (final item in json['items'] as List<dynamic>)
            PricePoint.fromJson(item as Map<String, dynamic>),
        ],
      );

  final ComparedProduct product;
  final HistoryStore store;
  final int days;

  /// The window the server looked at (its own clock, UTC).
  final DateTime from;
  final DateTime to;

  /// Oldest first, exactly as recorded.
  final List<PricePoint> points;
}
