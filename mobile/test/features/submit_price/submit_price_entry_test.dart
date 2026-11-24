import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:alusekis/features/stores/store_prices_cache.dart';
import 'package:alusekis/features/stores/store_prices_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// The whole app with a scripted server: the ways into "Atnaujinti kainą".
late FakeApiAdapter _adapter;

const _storePrices = '/api/v1/stores/1/prices';
const _comparison = '/api/v1/products/7/prices';
const _submit = '/api/v1/prices';

Map<String, Object> _storePage(int cents) => {
      'store': {'id': 1, 'name': 'Iki', 'address': 'Žirmūnų g. 64'},
      'items': [
        {
          'priceEntryId': 11,
          'productId': 7,
          'productName': 'Švyturys Ekstra',
          'volumeMl': 500,
          'priceCents': cents,
          'observedAt': '2026-11-22T10:30:00Z',
          'isStale': false,
        },
      ],
      'total': 1,
      'page': 1,
      'pageSize': 20,
    };

Map<String, Object> _offer(int id, int storeId, String store, int cents) => {
      'priceEntryId': id,
      'storeId': storeId,
      'storeName': store,
      'storeAddress': 'Gatvė $storeId',
      'priceCents': cents,
      'observedAt': '2026-11-20T10:30:00Z',
      'isStale': false,
    };

Map<String, Object> _comparisonBody(int lidlCents) => {
      'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'items': [_offer(21, 4, 'Lidl', lidlCents), _offer(22, 1, 'Iki', 149)],
      'storeCount': 2,
      'singleStore': false,
    };

Map<String, Object> _saved(int storeId, int cents) => {
      'id': 99,
      'productId': 7,
      'storeId': storeId,
      'priceCents': cents,
      'observedAt': '2026-11-24T10:30:00Z',
      'isLargeChange': false,
    };

Future<AppPreferences> _pumpApp(
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
  return prefs;
}

/// Stores tab -> marker "Iki" -> "Peržiūrėti kainas".
Future<void> _openStorePrices(WidgetTester tester) async {
  await tester.tap(find.text('pin Iki'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Peržiūrėti kainas'));
  await tester.pumpAndSettle();
}

/// "Atnaujinti kainą" buttons (TextButton.icon is a subclass of TextButton).
Finder _submitButtons() => find.ancestor(
      of: find.text('Atnaujinti kainą'),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );

TextButton _firstSubmitButton(WidgetTester tester) => tester.widget<TextButton>(_submitButtons().first);

Future<void> _savePrice(WidgetTester tester, String price) async {
  await tester.enterText(find.byType(TextField), price);
  await tester.tap(find.widgetWithText(FilledButton, 'Patvirtinti'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _adapter = FakeApiAdapter();
    scriptStoreReplies(_adapter);
    _adapter.reply('GET', '/api/v1/auth/me', body: meResponse());
  });

  testWidgets('store prices -> "Atnaujinti kainą" -> saved -> back to the list showing the new price',
      (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage(149));
    _adapter.reply('GET', _storePrices, body: _storePage(169)); // after the save
    _adapter.reply('POST', _submit, status: 201, body: _saved(1, 169));
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);
    expect(find.text(formatPrice(149)), findsOneWidget);

    await tester.tap(_submitButtons().first);
    await tester.pumpAndSettle();

    // The form, filled in with the product and the store of the row.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);
    expect(find.text('Dabartinė kaina: ${formatPrice(149)}'), findsOneWidget);

    await _savePrice(tester, '1,69');

    final sent = _adapter.requestsTo('POST', _submit).single.data as Map<String, dynamic>;
    expect(sent['productId'], 7);
    expect(sent['storeId'], 1);
    expect(sent['priceCents'], 169);
    // Back on the list, loaded again: the new price is shown.
    expect(find.byType(TextField), findsNothing);
    expect(_adapter.requestsTo('GET', _storePrices), hasLength(2));
    expect(find.text(formatPrice(169)), findsOneWidget);
    expect(find.text('Kaina išsaugota: ${formatPrice(169)}'), findsOneWidget);
  });

  testWidgets('not signed in: sent to sign in first, then straight back to the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage(149));
    _adapter.reply('POST', '/api/v1/auth/login', body: authResponse(token: 'fresh'));
    await _pumpApp(tester); // no stored token
    await _openStorePrices(tester);

    await tester.tap(_submitButtons().first);
    await tester.pumpAndSettle();

    // The sign-in screen, not the form.
    expect(find.widgetWithText(FilledButton, 'Prisijungti'), findsOneWidget);
    expect(find.text('Kaina, €'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'jonas@example.lt');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct horse battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Prisijungti'));
    await tester.pumpAndSettle();

    expect(_adapter.requestsTo('POST', '/api/v1/auth/login'), hasLength(1));
    expect(find.text('Kaina, €'), findsOneWidget); // the form opened by itself
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(_adapter.requestsTo('POST', _submit), isEmpty); // nothing sent yet
  });

  testWidgets('leaving the sign-in without signing in does not open the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage(149));
    await _pumpApp(tester);
    await _openStorePrices(tester);

    await tester.tap(_submitButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();

    expect(find.text('Kaina, €'), findsNothing);
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
    expect(_firstSubmitButton(tester).onPressed, isNull);
    expect(find.text('Be ryšio kainos atnaujinti negalima'), findsOneWidget);

    await tester.tap(_submitButtons().first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Kaina, €'), findsNothing);
  });

  testWidgets('with a connection the button is enabled and has no such note', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage(149));
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);

    expect(_firstSubmitButton(tester).onPressed, isNotNull);
    expect(find.text('Be ryšio kainos atnaujinti negalima'), findsNothing);
  });

  testWidgets('comparison -> "Atnaujinti kainą" on a store row -> saved -> the comparison reloads',
      (tester) async {
    _adapter.reply(
      'GET',
      '/api/v1/products/search',
      body: {
        'items': [
          {'id': 7, 'name': 'Švyturys Ekstra', 'volumeMl': 500, 'brand': 'Švyturys'},
        ],
      },
    );
    _adapter.reply('GET', _comparison, body: _comparisonBody(139));
    _adapter.reply('GET', _comparison, body: _comparisonBody(129)); // after the save
    _adapter.reply('POST', _submit, status: 201, body: _saved(4, 129));
    await _pumpApp(tester, storedToken: 'stored');

    await tester.tap(find.text('Paieška').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'švyturys');
    await tester.pump(searchDebounce + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Švyturys Ekstra'));
    await tester.pumpAndSettle();
    expect(find.text('Kainų palyginimas'), findsOneWidget);

    await tester.tap(_submitButtons().first); // the first row is Lidl (cheapest first)
    await tester.pumpAndSettle();

    expect(find.text('Lidl'), findsOneWidget);
    await _savePrice(tester, '1,29');

    final sent = _adapter.requestsTo('POST', _submit).single.data as Map<String, dynamic>;
    expect(sent['storeId'], 4);
    expect(sent['productId'], 7);
    expect(find.text('Kainų palyginimas'), findsOneWidget);
    expect(_adapter.requestsTo('GET', _comparison), hasLength(2));
    expect(find.text(formatPrice(129)), findsOneWidget);
  });
}
