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
      'from': '2026-10-24T12:00:00Z', // 15:00 in Vilnius (summer time still)
      'to': '2026-11-23T12:00:00Z',
      'items': items,
    };

Future<void> _pump(WidgetTester tester, FakeApiAdapter adapter) async {
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
      child: const MaterialApp(home: PriceHistoryScreen(productId: 7, storeId: 3)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  group('no entries in the period', () {
    testWidgets('says so, draws no chart and offers a longer period', (tester) async {
      adapter.reply('GET', _path, body: _history([]));

      await _pump(tester, adapter);

      expect(find.text('Per pasirinktą laikotarpį kainų įrašų nėra'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      // Opened on 30 d., so the next longer one (90 d.) is offered.
      expect(find.text('Rodyti ilgesnį laikotarpį (90 d.)'), findsOneWidget);
    });

    testWidgets('the offered longer period is loaded and shown', (tester) async {
      adapter.reply('GET', _path, body: _history([]));
      adapter.reply(
        'GET',
        _path,
        body: _history([_entry(1, 150, '2026-09-20T10:30:00Z')], days: 90),
      );
      await _pump(tester, adapter);

      await tester.tap(find.text('Rodyti ilgesnį laikotarpį (90 d.)'));
      await tester.pumpAndSettle();

      expect(adapter.requestsTo('GET', _path).last.queryParameters, {'days': 90});
      expect(find.text('Per pasirinktą laikotarpį kainų įrašų nėra'), findsNothing);
      // 10:30 UTC on 20 September is 13:30 in Vilnius (summer time, UTC+3).
      expect(find.text('2026-09-20 13:30'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('from 7 d. the next longer one is 30 d.', (tester) async {
      adapter.reply('GET', _path, body: _history([_entry(1, 150, '2026-11-10T10:30:00Z')]));
      adapter.reply('GET', _path, body: _history([], days: 7));
      await _pump(tester, adapter);

      await tester.tap(find.text('7 d.'));
      await tester.pumpAndSettle();

      expect(find.text('Rodyti ilgesnį laikotarpį (30 d.)'), findsOneWidget);
    });

    testWidgets('at 90 d. there is no longer period to offer', (tester) async {
      adapter.reply('GET', _path, body: _history([_entry(1, 150, '2026-11-10T10:30:00Z')]));
      adapter.reply('GET', _path, body: _history([], days: 90));
      await _pump(tester, adapter);

      await tester.tap(find.text('90 d.'));
      await tester.pumpAndSettle();

      expect(find.text('Per pasirinktą laikotarpį kainų įrašų nėra'), findsOneWidget);
      expect(find.textContaining('Rodyti ilgesnį laikotarpį'), findsNothing);
    });
  });

  group('one entry', () {
    testWidgets('is one point, with a note saying only one price was recorded',
        (tester) async {
      adapter.reply('GET', _path, body: _history([_entry(1, 149, '2026-11-10T10:30:00Z')]));

      await _pump(tester, adapter);

      expect(find.text('Užregistruotas vienas kainos įrašas'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget); // text and icon, not colour
      final line = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single;
      expect(line.spots, hasLength(1));
      expect(line.spots.single.y, 149);
      expect(line.dotData.show, isTrue); // a single point is still visible
      expect(find.text('2026-11-10 12:30'), findsOneWidget);
      expect(find.text(formatPrice(149)), findsAtLeastNWidgets(1));
      expect(find.text('Per pasirinktą laikotarpį kainų įrašų nėra'), findsNothing);
    });

    testWidgets('several entries carry no such note', (tester) async {
      adapter.reply(
        'GET',
        _path,
        body: _history([
          _entry(1, 150, '2026-11-10T10:30:00Z'),
          _entry(2, 150, '2026-11-12T10:30:00Z'),
        ]),
      );

      await _pump(tester, adapter);

      expect(find.text('Užregistruotas vienas kainos įrašas'), findsNothing);
      final line = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single;
      expect(line.spots, hasLength(2)); // the same price twice: two points
    });
  });

  group('dates and marks', () {
    testWidgets('the list and the chart axis use YYYY-MM-DD HH:mm in Vilnius time',
        (tester) async {
      adapter.reply('GET', _path, body: _history([_entry(1, 150, '2026-11-10T10:30:00Z')]));

      await _pump(tester, adapter);

      // List: 10:30 UTC is 12:30 in Vilnius in winter.
      expect(find.text('2026-11-10 12:30'), findsOneWidget);
      // Axis: the start of the window (12:00 UTC on 24 Oct is 15:00 in Vilnius, summer time),
      // the same format with the time on a second line.
      expect(find.text('2026-10-24\n15:00'), findsOneWidget);
      expect(find.text('2026-11-23\n14:00'), findsOneWidget); // winter time again
    });

    testWidgets('a history has no "stale price" marks', (tester) async {
      adapter.reply(
        'GET',
        _path,
        body: _history([_entry(1, 150, '2026-09-30T10:30:00Z')]), // old, but that is just a date
      );

      await _pump(tester, adapter);

      expect(find.textContaining('Neatnaujinta'), findsNothing);
      expect(find.byIcon(Icons.schedule), findsNothing);
    });
  });
}
