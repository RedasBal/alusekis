import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:alusekis/features/stores/store_prices_cache.dart';
import 'package:alusekis/features/stores/store_prices_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// The whole app with a scripted server: the way into "Pridėti produktą".
late FakeApiAdapter _adapter;

const _storePrices = '/api/v1/stores/1/prices';
const _products = '/api/v1/products';
const _prices = '/api/v1/prices';

Map<String, Object> _storePage(List<Map<String, Object>> items) => {
      'store': {'id': 1, 'name': 'Iki', 'address': 'Žirmūnų g. 64'},
      'items': items,
      'total': items.length,
      'page': 1,
      'pageSize': 20,
    };

Map<String, Object> _storeItem(int productId, String name, int cents) => {
      'priceEntryId': 10 + productId,
      'productId': productId,
      'productName': name,
      'volumeMl': 500,
      'priceCents': cents,
      'observedAt': '2026-11-22T10:30:00Z',
      'isStale': false,
    };

Map<String, Object> _created() => {
      'product': {'id': 70, 'name': 'Žalgiris', 'volumeMl': 500},
      'price': {
        'id': 61,
        'productId': 70,
        'storeId': 1,
        'priceCents': 199,
        'observedAt': '2026-11-24T10:30:00Z',
        'isLargeChange': false,
      },
    };

Future<void> _pumpApp(
  WidgetTester tester, {
  String? storedToken,
  Future<void> Function(AppPreferences prefs)? beforeStart,
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  await beforeStart?.call(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage(storedToken)),
        httpClientAdapterProvider.overrideWithValue(_adapter),
        mapProviderProvider.overrideWithValue(const FakeMapProvider()),
      ],
      child: const AlusekisApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Stores tab -> marker "Iki" -> "Peržiūrėti kainas".
Future<void> _openStorePrices(WidgetTester tester) async {
  await tester.tap(find.text('pin Iki'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Peržiūrėti kainas'));
  await tester.pumpAndSettle();
}

Finder _addButton() => find.widgetWithText(OutlinedButton, 'Pridėti produktą');

Future<void> _fillAndConfirm(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Pavadinimas *'), 'ŽALGIRIS');
  await tester.enterText(find.widgetWithText(TextField, 'Talpa *'), '500');
  await tester.enterText(find.widgetWithText(TextField, 'Kaina, € *'), '1,99');
  await tester.tap(find.widgetWithText(FilledButton, 'Patvirtinti'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _adapter = FakeApiAdapter();
    scriptStoreReplies(_adapter);
    _adapter.reply('GET', '/api/v1/auth/me', body: meResponse());
  });

  testWidgets('store prices -> "Pridėti produktą" -> saved -> back to the list showing the new product',
      (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage([_storeItem(7, 'Švyturys Ekstra', 149)]));
    _adapter.reply(
      'GET',
      _storePrices,
      body: _storePage([_storeItem(7, 'Švyturys Ekstra', 149), _storeItem(70, 'Žalgiris', 199)]),
    );
    _adapter.reply('POST', _products, status: 201, body: _created());
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);

    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // The form, with the store of the list already filled in.
    expect(find.text('Talpa *'), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);

    await _fillAndConfirm(tester);

    final sent = _adapter.requestsTo('POST', _products).single.data as Map<String, dynamic>;
    expect(sent['storeId'], 1);
    expect(sent['name'], 'ŽALGIRIS');
    expect(sent['volumeMl'], 500);
    expect(sent['priceCents'], 199);
    // Back on the list, loaded again: the new product and its price are shown.
    expect(find.text('Talpa *'), findsNothing);
    expect(_adapter.requestsTo('GET', _storePrices), hasLength(2));
    expect(find.text('Žalgiris'), findsOneWidget);
    expect(find.text(formatPrice(199)), findsOneWidget);
  });

  testWidgets('not signed in: sent to sign in first, then straight back to the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage([_storeItem(7, 'Švyturys Ekstra', 149)]));
    _adapter.reply('POST', '/api/v1/auth/login', body: authResponse(token: 'fresh'));
    await _pumpApp(tester); // no stored token
    await _openStorePrices(tester);

    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    // The sign-in screen, not the form.
    expect(find.widgetWithText(FilledButton, 'Prisijungti'), findsOneWidget);
    expect(find.text('Talpa *'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'jonas@example.lt');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct horse battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Prisijungti'));
    await tester.pumpAndSettle();

    expect(_adapter.requestsTo('POST', '/api/v1/auth/login'), hasLength(1));
    expect(find.text('Talpa *'), findsOneWidget); // the form opened by itself
    expect(find.text('Iki'), findsOneWidget);
    expect(_adapter.requestsTo('POST', _products), isEmpty); // nothing sent yet
  });

  testWidgets('leaving the sign-in without signing in does not open the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage([_storeItem(7, 'Švyturys Ekstra', 149)]));
    await _pumpApp(tester);
    await _openStorePrices(tester);

    await tester.tap(_addButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();

    expect(find.text('Talpa *'), findsNothing);
    expect(find.text(formatPrice(149)), findsOneWidget); // back on the store's prices
  });

  testWidgets('without a connection the button is disabled and says why', (tester) async {
    _adapter.replaceWithOffline('GET', _storePrices);
    await _pumpApp(
      tester,
      storedToken: 'stored',
      beforeStart: (prefs) => StorePricesCache(prefs).write(
        1,
        PricesSnapshot(
          store: const StoreSummary(id: 1, name: 'Iki', address: 'Žirmūnų g. 64'),
          items: [
            StorePrice(
              priceEntryId: 11,
              productId: 7,
              productName: 'Švyturys Ekstra',
              volumeMl: 500,
              priceCents: 149,
              observedAt: DateTime.utc(2026, 11, 22, 10, 30),
              isStale: false,
            ),
          ],
          total: 1,
          syncedAt: DateTime.utc(2026, 11, 22, 12),
        ),
      ),
    );
    await _openStorePrices(tester);

    expect(find.textContaining('Rodomi išsaugoti duomenys'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_addButton()).onPressed, isNull);
    expect(find.text('Be ryšio produktų pridėti negalima'), findsOneWidget);

    await tester.tap(_addButton(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Talpa *'), findsNothing);
  });

  testWidgets('with a connection the button is enabled and has no such note', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage([_storeItem(7, 'Švyturys Ekstra', 149)]));
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);

    expect(tester.widget<OutlinedButton>(_addButton()).onPressed, isNotNull);
    expect(find.text('Be ryšio produktų pridėti negalima'), findsNothing);
  });

  testWidgets('a duplicate opens the price form of the existing product for the same store',
      (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage([_storeItem(9, 'Žalgiris', 149)]));
    _adapter.reply(
      'POST',
      _products,
      status: 409,
      body: {
        'code': 'product_exists',
        'message': 'server text',
        'requestId': 'r',
        'existingProduct': {'id': 9, 'name': 'Žalgiris', 'volumeMl': 500},
      },
    );
    _adapter.reply(
      'POST',
      _prices,
      status: 201,
      body: {
        'id': 62,
        'productId': 9,
        'storeId': 1,
        'priceCents': 159,
        'observedAt': '2026-11-24T10:30:00Z',
        'isLargeChange': false,
      },
    );
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);
    await tester.tap(_addButton());
    await tester.pumpAndSettle();

    await _fillAndConfirm(tester); // "ŽALGIRIS" is the same product as "Žalgiris"

    expect(
      find.text('Toks produktas jau yra: Žalgiris, 500 ml. Norite atnaujinti jo kainą?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Atnaujinti kainą'));
    await tester.pumpAndSettle();

    // The price form of the existing product, in the same store.
    expect(find.text('Kaina, €'), findsOneWidget);
    expect(find.text('Žalgiris'), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1,59');
    await tester.tap(find.widgetWithText(FilledButton, 'Patvirtinti'));
    await tester.pumpAndSettle();

    final sent = _adapter.requestsTo('POST', _prices).single.data as Map<String, dynamic>;
    expect(sent['productId'], 9);
    expect(sent['storeId'], 1);
    expect(sent['priceCents'], 159);
    expect(find.text('Talpa *'), findsNothing); // both forms are closed again
  });
}
