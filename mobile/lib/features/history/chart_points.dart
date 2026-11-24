import 'history_models.dart';

/// A point on the chart: x is milliseconds since the epoch (UTC), y is the
/// price in euro cents.
class ChartPoint {
  const ChartPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is ChartPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ChartPoint($x, $y)';
}

/// The chart's points: **exactly one per recorded price**, in the order given.
///
/// Nothing is invented: no points between recorded ones, none for days
/// without an entry, no averaging, and equal prices stay separate points.
List<ChartPoint> buildChartPoints(List<PricePoint> points) => [
      for (final point in points)
        ChartPoint(
          point.observedAt.millisecondsSinceEpoch.toDouble(),
          point.priceCents.toDouble(),
        ),
    ];

/// The visible area of the chart. This only chooses how much of the plane is
/// shown; it adds no data.
class ChartBounds {
  const ChartBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

/// Spacing of the price labels on the vertical axis: a multiple of 5 cents,
/// about four labels over the visible range.
double yAxisIntervalCents(ChartBounds bounds) {
  final raw = (bounds.maxY - bounds.minY) / 4;
  return raw <= 5 ? 5 : (raw / 5).ceil() * 5.0;
}

/// Bounds that show the whole window the server looked at and every price,
/// with some room above and below so the points do not sit on the edges.
///
/// Never degenerate: a single price (or all prices equal) still gets a
/// non-empty price range.
ChartBounds chartBoundsFor(PriceHistory history, List<ChartPoint> chartPoints) {
  var minX = history.from.millisecondsSinceEpoch.toDouble();
  var maxX = history.to.millisecondsSinceEpoch.toDouble();
  var minY = double.infinity;
  var maxY = double.negativeInfinity;

  for (final point in chartPoints) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }

  if (maxX <= minX) {
    maxX = minX + const Duration(days: 1).inMilliseconds;
  }

  if (chartPoints.isEmpty) {
    minY = 0;
    maxY = 100;
  } else {
    final spread = maxY - minY;
    // At least 10 cents of room; otherwise a tenth of the spread.
    final pad = spread == 0 ? 10.0 : (spread * 0.1 < 5 ? 5.0 : spread * 0.1);
    minY = (minY - pad).clamp(0, double.infinity).toDouble();
    maxY = maxY + pad;
  }

  return ChartBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}
