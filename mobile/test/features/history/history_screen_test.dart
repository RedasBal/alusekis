import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/history/history_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/products/7/stores/3/history';

Map<String, Object> _entry(int id, int cents, String observedAt) =>
    {'priceEntryId': id, 'priceCents': cents, 'observedAt': observedAt};

Map<String, Object> _history(List<Object> items, {int days = 30}) => {
      'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'store': {'id': 3, 'name': 'Maxima XX', 'address': 'Ukmergės g. 282'},
      'days': days,
      'from': '2026-10-24T12:00:00Z',
      'to': '2026-11-23T12:00:00Z',
      'items': items,
    };

// 10:30 UTC is 12:30 in Vilnius in winter.
final _first = _entry(1, 150, '2026-11-10T10:30:00Z');
final _second = _entry(2, 140, '2026-11-15T10:30:00Z');
final _third = _entry(3, 140, '2026-11-20T10:30:00Z'); // same price again

Future<void> _pump(WidgetTester tester, FakeApiAdapter adapter) async {
  // A tall screen, so the lazily built list shows all rows below the chart.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        httpClientAdapterProvider.overrideWithValue(adapter),
      ],
      child: const MaterialApp(
        home: PriceHistoryScreen(
          productId: 7,
          storeId: 3,
          productName: 'Švyturys Ekstra',
          volumeMl: 500,
          storeName: 'Maxima XX',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LineChartBarData _line(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single;

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('shows the product, the store and the period choice with 30 d. first',
      (tester) async {
    adapter.reply('GET', _path, body: _history([_first, _second]));

    await _pump(tester, adapter);

    expect(find.text('Kainų istorija'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.text('Maxima XX, Ukmergės g. 282'), findsOneWidget);
    for (final label in ['7 d.', '30 d.', '90 d.']) {
      expect(find.text(label), findsOneWidget);
    }
    final selector = tester.widget<SegmentedButton<dynamic>>(
      find.byWidgetPredicate((widget) => widget is SegmentedButton<dynamic>),
    );
    expect(selector.selected.single.toString(), contains('month'));
    expect(adapter.requestsTo('GET', _path).single.queryParameters, {'days': 30});
  });

  testWidgets('the chart has one point per recorded price and only straight lines',
      (tester) async {
    adapter.reply('GET', _path, body: _history([_first, _second, _third]));

    await _pump(tester, adapter);

    final line = _line(tester);
    expect(line.spots, hasLength(3)); // not one more: nothing between entries, same price kept
    expect(line.spots.map((s) => s.y), [150, 140, 140]);
    expect(line.isCurved, isFalse);
    expect(line.dotData.show, isTrue);
  });

  testWidgets('lists the recorded prices oldest first with date and price', (tester) async {
    adapter.reply('GET', _path, body: _history([_first, _second, _third]));

    await _pump(tester, adapter);

    expect(find.text('2026-11-10 12:30'), findsOneWidget);
    expect(find.text('2026-11-15 12:30'), findsOneWidget);
    expect(find.text('2026-11-20 12:30'), findsOneWidget);
    // A price can also appear as a label on the chart's price axis, so count
    // at least the rows: one entry at 1,50 and two at 1,40.
    expect(find.text(formatPrice(150)), findsAtLeastNWidgets(1));
    expect(find.text(formatPrice(140)), findsAtLeastNWidgets(2));
    final firstDate = tester.getTopLeft(find.text('2026-11-10 12:30')).dy;
    final lastDate = tester.getTopLeft(find.text('2026-11-20 12:30')).dy;
    expect(firstDate, lessThan(lastDate));
  });

  testWidgets('changing the period asks the server again with that period',
      (tester) async {
    adapter.reply('GET', _path, body: _history([_first, _second]));
    adapter.reply('GET', _path, body: _history([_second], days: 7));
    await _pump(tester, adapter);
    expect(_line(tester).spots, hasLength(2));

    await tester.tap(find.text('7 d.'));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path).last.queryParameters, {'days': 7});
    expect(_line(tester).spots, hasLength(1));
    expect(find.text('2026-11-10 12:30'), findsNothing); // only the entry of that period
    expect(find.text('2026-11-15 12:30'), findsOneWidget);

    adapter.replace('GET', _path, body: _history([_first, _second, _third], days: 90));
    await tester.tap(find.text('90 d.'));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path).last.queryParameters, {'days': 90});
    expect(_line(tester).spots, hasLength(3));
  });

  testWidgets('choosing the period already shown sends nothing new', (tester) async {
    adapter.reply('GET', _path, body: _history([_first, _second]));
    await _pump(tester, adapter);

    await tester.tap(find.text('30 d.'));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path), hasLength(1));
  });

  testWidgets('an error is explained without technical details and can be retried',
      (tester) async {
    adapter.replyError('GET', _path, 500, 'internal_error');
    adapter.reply('GET', _path, body: _history([_first, _second]));

    await _pump(tester, adapter);

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('internal_error'), findsNothing);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);

    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });
}
