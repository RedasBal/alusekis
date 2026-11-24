import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// The whole app with a scripted server: the flows that lead to a comparison.
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

void _scriptServer() {
  _adapter = FakeApiAdapter();
  scriptStoreReplies(_adapter); // cities and the stores "Iki" (id 1) and "Maxima XX" (id 2)

  // Search finds one product.
  _adapter.reply(
    'GET',
    '/api/v1/products/search',
    body: {
      'items': [
        {'id': 7, 'name': 'Švyturys Ekstra', 'volumeMl': 500, 'brand': 'Švyturys'},
      ],
    },
  );

  // The prices of store 1 include that product.
  _adapter.reply(
    'GET',
    '/api/v1/stores/1/prices',
    body: {
      'store': {'id': 1, 'name': 'Iki', 'address': 'Žirmūnų g. 64'},
      'items': [
        {
          'priceEntryId': 11,
          'productId': 7,
          'productName': 'Švyturys Ekstra',
          'volumeMl': 500,
          'priceCents': 149,
          'observedAt': '2026-11-22T10:30:00Z',
          'isStale': false,
        },
      ],
      'total': 1,
      'page': 1,
      'pageSize': 20,
    },
  );

  // The comparison of that product in two stores.
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
}

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
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

void main() {
  setUp(_scriptServer);

  testWidgets('search -> product -> comparison, and back to the search results',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Paieška').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'švyturys');
    await tester.pump(searchDebounce + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Švyturys Ekstra'), findsOneWidget);

    await tester.tap(find.text('Švyturys Ekstra'));
    await tester.pumpAndSettle();

    // The comparison of that product (its id, not another volume's).
    expect(find.text('Kainų palyginimas'), findsOneWidget);
    expect(find.text('500 ml · Švyturys'), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text(formatPrice(139)), findsOneWidget);
    expect(find.text('Pigiausia'), findsOneWidget);
    expect(_adapter.requestsTo('GET', '/api/v1/products/7/prices').single.queryParameters, {
      'sort': 'asc',
    });

    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();

    expect(find.text('Kainų palyginimas'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget); // the results are still there
  });

  testWidgets('store -> its prices -> product -> comparison, and back again',
      (tester) async {
    await _pumpApp(tester);

    // Stores tab (the start screen, on the map): tap a marker, then "Peržiūrėti kainas".
    await tester.tap(find.text('pin Iki'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peržiūrėti kainas'));
    await tester.pumpAndSettle();
    expect(find.text('Žirmūnų g. 64'), findsNothing); // the store price list, not the sheet
    expect(find.text('Švyturys Ekstra'), findsOneWidget);

    await tester.tap(find.text('Švyturys Ekstra'));
    await tester.pumpAndSettle();

    expect(find.text('Kainų palyginimas'), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);
    expect(_adapter.requestsTo('GET', '/api/v1/products/7/prices'), hasLength(1));

    // Back to the store's prices, then to the stores.
    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();
    expect(find.text('Kainų palyginimas'), findsNothing);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);

    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();
    expect(find.text('Naudoti vietą'), findsOneWidget);
  });
}
