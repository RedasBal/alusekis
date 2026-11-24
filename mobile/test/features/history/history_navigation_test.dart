import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// The whole app with a scripted server: search -> product -> comparison -> history.
late FakeApiAdapter _adapter;

Map<String, Object> _offer(int id, int storeId, String store, int cents) => {
      'priceEntryId': id,
      'storeId': storeId,
      'storeName': store,
      'storeAddress': 'Gatvė $storeId',
      'priceCents': cents,
      'observedAt': '2026-11-20T10:30:00Z',
      'isStale': false,
    };

Map<String, Object> _history(int storeId, String store, List<Object> items) => {
      'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'store': {'id': storeId, 'name': store, 'address': 'Gatvė $storeId'},
      'days': 30,
      'from': '2026-10-24T12:00:00Z',
      'to': '2026-11-23T12:00:00Z',
      'items': items,
    };

void _scriptServer() {
  _adapter = FakeApiAdapter();
  scriptStoreReplies(_adapter);

  _adapter.reply(
    'GET',
    '/api/v1/products/search',
    body: {
      'items': [
        {'id': 7, 'name': 'Švyturys Ekstra', 'volumeMl': 500, 'brand': 'Švyturys'},
      ],
    },
  );

  _adapter.reply(
    'GET',
    '/api/v1/products/7/prices',
    body: {
      'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'items': [_offer(21, 4, 'Lidl', 139), _offer(22, 1, 'Iki', 149)],
      'storeCount': 2,
      'singleStore': false,
    },
  );

  // The history of that product in each of the two stores (different data).
  _adapter.reply(
    'GET',
    '/api/v1/products/7/stores/4/history',
    body: _history(4, 'Lidl', [
      {'priceEntryId': 31, 'priceCents': 145, 'observedAt': '2026-11-01T10:30:00Z'},
      {'priceEntryId': 32, 'priceCents': 139, 'observedAt': '2026-11-15T10:30:00Z'},
    ]),
  );
  _adapter.reply(
    'GET',
    '/api/v1/products/7/stores/1/history',
    body: _history(1, 'Iki', [
      {'priceEntryId': 41, 'priceCents': 149, 'observedAt': '2026-11-08T10:30:00Z'},
    ]),
  );
}

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        httpClientAdapterProvider.overrideWithValue(_adapter),
        mapProviderProvider.overrideWithValue(const FakeMapProvider()),
      ],
      child: const AlusekisApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openComparisonFromSearch(WidgetTester tester) async {
  await tester.tap(find.text('Paieška').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'švyturys');
  await tester.pump(searchDebounce + const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Švyturys Ekstra'));
  await tester.pumpAndSettle();
  expect(find.text('Kainų palyginimas'), findsOneWidget);
}

void main() {
  setUp(_scriptServer);

  testWidgets('comparison -> a store row -> that store\'s history, and back', (tester) async {
    await _pumpApp(tester);
    await _openComparisonFromSearch(tester);

    await tester.tap(find.text('Lidl'));
    await tester.pumpAndSettle();

    // The history of this product (7) in this store (4), 30 days.
    expect(find.text('Kainų istorija'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.textContaining('Lidl'), findsOneWidget);
    expect(find.text('2026-11-01 12:30'), findsOneWidget);
    expect(find.text('2026-11-15 12:30'), findsOneWidget);
    final line = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single;
    expect(line.spots, hasLength(2));
    expect(
      _adapter.requestsTo('GET', '/api/v1/products/7/stores/4/history').single.queryParameters,
      {'days': 30},
    );

    // Back to the comparison, then to the search.
    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();
    expect(find.text('Kainų istorija'), findsNothing);
    expect(find.text('Kainų palyginimas'), findsOneWidget);

    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();
    expect(find.text('Kainų palyginimas'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('each store row opens the history of its own store', (tester) async {
    await _pumpApp(tester);
    await _openComparisonFromSearch(tester);

    await tester.tap(find.text('Iki'));
    await tester.pumpAndSettle();

    // Store 1 ("Iki") has a single recorded price.
    expect(
      _adapter.requestsTo('GET', '/api/v1/products/7/stores/1/history'),
      hasLength(1),
    );
    expect(_adapter.requestsTo('GET', '/api/v1/products/7/stores/4/history'), isEmpty);
    expect(find.text('Užregistruotas vienas kainos įrašas'), findsOneWidget);
    expect(find.text('2026-11-08 12:30'), findsOneWidget);
  });
}
