import 'package:alusekis/features/history/chart_points.dart';
import 'package:alusekis/features/history/history_models.dart';
import 'package:flutter_test/flutter_test.dart';

PricePoint _point(int id, int cents, DateTime observedAt) =>
    PricePoint(priceEntryId: id, priceCents: cents, observedAt: observedAt);

PriceHistory _history(List<PricePoint> points, {int days = 30}) => PriceHistory.fromJson({
      'product': {'id': 1, 'name': 'Alus', 'volumeMl': 500},
      'store': {'id': 1, 'name': 'Maxima XX', 'address': 'Gatvė 1'},
      'days': days,
      'from': '2026-10-24T12:00:00Z',
      'to': '2026-11-23T12:00:00Z',
      'items': <Object>[
        for (final p in points)
          {
            'priceEntryId': p.priceEntryId,
            'priceCents': p.priceCents,
            'observedAt': p.observedAt.toIso8601String(),
          },
      ],
    });

final _t0 = DateTime.utc(2026, 11, 10, 9);

void main() {
  group('buildChartPoints: one point per recorded price, nothing invented', () {
    test('no entries give no points', () {
      expect(buildChartPoints([]), isEmpty);
    });

    test('one entry gives exactly one point', () {
      final points = buildChartPoints([_point(1, 149, _t0)]);

      expect(points, hasLength(1));
      expect(points.single.y, 149);
      expect(points.single.x, _t0.millisecondsSinceEpoch.toDouble());
    });

    test('there are as many points as entries, in the order given', () {
      final entries = [
        _point(1, 150, _t0),
        _point(2, 140, _t0.add(const Duration(days: 3))),
        _point(3, 160, _t0.add(const Duration(days: 9))),
      ];

      final points = buildChartPoints(entries);

      expect(points, hasLength(3)); // none between the entries, even with 6 empty days gaps
      expect(points.map((p) => p.y), [150, 140, 160]);
      expect(points.map((p) => p.x), [
        for (final e in entries) e.observedAt.millisecondsSinceEpoch.toDouble(),
      ]);
    });

    test('the same price in several entries stays several points', () {
      final points = buildChartPoints([
        _point(1, 150, _t0),
        _point(2, 150, _t0.add(const Duration(days: 1))),
        _point(3, 150, _t0.add(const Duration(days: 2))),
      ]);

      expect(points, hasLength(3));
      expect(points.map((p) => p.y).toSet(), {150.0});
    });

    test('two entries at the very same moment stay two points', () {
      final points = buildChartPoints([_point(1, 150, _t0), _point(2, 155, _t0)]);

      expect(points, hasLength(2));
    });

    test('a price is exactly its cents, not rounded or converted', () {
      final points = buildChartPoints([_point(1, 1, _t0), _point(2, 50000, _t0)]);

      expect(points.map((p) => p.y), [1, 50000]);
    });
  });

  group('chartBoundsFor: only the visible area, no data', () {
    test('contains every point and the whole window', () {
      final history = _history([
        _point(1, 120, DateTime.utc(2026, 10, 30)),
        _point(2, 180, DateTime.utc(2026, 11, 20)),
      ]);
      final points = buildChartPoints(history.points);

      final bounds = chartBoundsFor(history, points);

      for (final p in points) {
        expect(p.x, inInclusiveRange(bounds.minX, bounds.maxX));
        expect(p.y, inInclusiveRange(bounds.minY, bounds.maxY));
      }
      expect(bounds.minX, history.from.millisecondsSinceEpoch.toDouble());
      expect(bounds.maxX, history.to.millisecondsSinceEpoch.toDouble());
      expect(bounds.minY, lessThan(120));
      expect(bounds.maxY, greaterThan(180));
      expect(bounds.minY, greaterThanOrEqualTo(0));
    });

    test('a single price still gets a visible price range', () {
      final history = _history([_point(1, 149, DateTime.utc(2026, 11, 10))]);

      final bounds = chartBoundsFor(history, buildChartPoints(history.points));

      expect(bounds.maxY, greaterThan(bounds.minY));
      expect(149, inInclusiveRange(bounds.minY, bounds.maxY));
    });

    test('equal prices still get a visible price range', () {
      final history = _history([
        _point(1, 150, DateTime.utc(2026, 11, 1)),
        _point(2, 150, DateTime.utc(2026, 11, 5)),
      ]);

      final bounds = chartBoundsFor(history, buildChartPoints(history.points));

      expect(bounds.maxY, greaterThan(bounds.minY));
    });

    test('the price range never goes below zero', () {
      final history = _history([_point(1, 1, DateTime.utc(2026, 11, 10))]);

      final bounds = chartBoundsFor(history, buildChartPoints(history.points));

      expect(bounds.minY, greaterThanOrEqualTo(0));
    });

    test('the axis label spacing is a positive multiple of 5 cents', () {
      final history = _history([
        _point(1, 100, DateTime.utc(2026, 11, 1)),
        _point(2, 400, DateTime.utc(2026, 11, 5)),
      ]);
      final bounds = chartBoundsFor(history, buildChartPoints(history.points));

      final interval = yAxisIntervalCents(bounds);

      expect(interval, greaterThan(0));
      expect(interval % 5, 0);
    });
  });

  group('models', () {
    test('the periods are 7, 30 and 90 days with their labels; 30 is the default', () {
      expect(HistoryPeriod.values.map((p) => p.days), [7, 30, 90]);
      expect(HistoryPeriod.values.map((p) => p.label), ['7 d.', '30 d.', '90 d.']);
      expect(HistoryPeriod.defaultPeriod, HistoryPeriod.month);
    });

    test('a history is read as the server sends it', () {
      final history = _history([_point(7, 149, _t0)], days: 7);

      expect(history.days, 7);
      expect(history.product.name, 'Alus');
      expect(history.store.name, 'Maxima XX');
      expect(history.from, DateTime.utc(2026, 10, 24, 12));
      expect(history.to.isUtc, isTrue);
      expect(history.points.single.priceEntryId, 7);
      expect(history.points.single.observedAt, _t0);
    });
  });
}
