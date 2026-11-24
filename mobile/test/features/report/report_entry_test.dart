import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/report/report_screen.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:alusekis/features/stores/store_prices_cache.dart';
import 'package:alusekis/features/stores/store_prices_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// The whole app with a scripted server: the ways into "Pranešti apie klaidą".
late FakeApiAdapter _adapter;

const _storePrices = '/api/v1/stores/1/prices';
const _comparison = '/api/v1/products/7/prices';
const _reports = '/api/v1/reports';

Map<String, Object> _storePage() => {
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

Map<String, Object> _comparisonBody() => {
      'product': {'id': 7, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'items': [_offer(21, 4, 'Lidl', 139), _offer(22, 1, 'Iki', 149)],
      'storeCount': 2,
      'singleStore': false,
    };

Map<String, Object> _stored() => {
      'reportId': 5,
      'status': 'New',
      'submittedAt': '2026-11-24T10:30:00Z',
    };

Future<void> _pumpApp(
  WidgetTester tester, {
  String? storedToken,
  Future<void> Function(AppPreferences prefs)? beforeStart,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
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

/// "Pranešti apie klaidą" buttons (TextButton.icon is a subclass of TextButton).
Finder _reportButtons() => find.ancestor(
      of: find.text('Pranešti apie klaidą'),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );

Future<void> _fillAndSend(WidgetTester tester) async {
  await tester.tap(find.text('Neteisinga kaina'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Lentynoje kita kaina');
  await tester.tap(find.widgetWithText(FilledButton, 'Pateikti'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _adapter = FakeApiAdapter();
    scriptStoreReplies(_adapter);
    _adapter.reply('GET', '/api/v1/auth/me', body: meResponse());
  });

  testWidgets('store prices -> "Pranešti apie klaidą" -> sent -> back on the list, price unchanged',
      (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage());
    _adapter.reply('POST', _reports, status: 201, body: _stored());
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);

    await tester.tap(_reportButtons().first);
    await tester.pumpAndSettle();

    // The form shows the price of the row.
    expect(find.text('Priežastis *'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);
    expect(find.text(formatPrice(149)), findsOneWidget);

    await _fillAndSend(tester);

    final sent = _adapter.requestsTo('POST', _reports).single.data as Map<String, dynamic>;
    expect(sent['priceEntryId'], 11);
    expect(sent['reason'], 'WrongPrice');
    expect(sent['comment'], 'Lentynoje kita kaina');
    // Back on the list: the price is exactly as before, and it was not reloaded.
    expect(find.text('Priežastis *'), findsNothing);
    expect(find.text(formatPrice(149)), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(_adapter.requestsTo('GET', _storePrices), hasLength(1));
    expect(find.text(reportSentMessage), findsOneWidget);
  });

  testWidgets('not signed in: sent to sign in first, then straight back to the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage());
    _adapter.reply('POST', '/api/v1/auth/login', body: authResponse(token: 'fresh'));
    await _pumpApp(tester); // no stored token
    await _openStorePrices(tester);

    await tester.tap(_reportButtons().first);
    await tester.pumpAndSettle();

    // The sign-in screen, not the form.
    expect(find.widgetWithText(FilledButton, 'Prisijungti'), findsOneWidget);
    expect(find.text('Priežastis *'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'jonas@example.lt');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct horse battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Prisijungti'));
    await tester.pumpAndSettle();

    expect(_adapter.requestsTo('POST', '/api/v1/auth/login'), hasLength(1));
    expect(find.text('Priežastis *'), findsOneWidget); // the form opened by itself
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(_adapter.requestsTo('POST', _reports), isEmpty); // nothing sent yet
  });

  testWidgets('leaving the sign-in without signing in does not open the form', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage());
    await _pumpApp(tester);
    await _openStorePrices(tester);

    await tester.tap(_reportButtons().first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Atgal'));
    await tester.pumpAndSettle();

    expect(find.text('Priežastis *'), findsNothing);
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
    expect(tester.widget<TextButton>(_reportButtons().first).onPressed, isNull);
    expect(find.text('Be ryšio pranešti negalima'), findsOneWidget);

    await tester.tap(_reportButtons().first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Priežastis *'), findsNothing);
  });

  testWidgets('with a connection the button is enabled and has no such note', (tester) async {
    _adapter.reply('GET', _storePrices, body: _storePage());
    await _pumpApp(tester, storedToken: 'stored');
    await _openStorePrices(tester);

    expect(tester.widget<TextButton>(_reportButtons().first).onPressed, isNotNull);
    expect(find.text('Be ryšio pranešti negalima'), findsNothing);
  });

  testWidgets('comparison -> "Pranešti apie klaidą" on a store row reports that store\'s price entry',
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
    _adapter.reply('GET', _comparison, body: _comparisonBody());
    _adapter.reply('POST', _reports, status: 201, body: _stored());
    await _pumpApp(tester, storedToken: 'stored');

    await tester.tap(find.text('Paieška').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'švyturys');
    await tester.pump(searchDebounce + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Švyturys Ekstra'));
    await tester.pumpAndSettle();
    expect(find.text('Kainų palyginimas'), findsOneWidget);

    await tester.tap(_reportButtons().first); // the first row is Lidl (cheapest first)
    await tester.pumpAndSettle();

    expect(find.text('Priežastis *'), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text(formatPrice(139)), findsOneWidget);

    await _fillAndSend(tester);

    final sent = _adapter.requestsTo('POST', _reports).single.data as Map<String, dynamic>;
    expect(sent['priceEntryId'], 21); // Lidl's price entry
    expect(find.text('Kainų palyginimas'), findsOneWidget);
    expect(_adapter.requestsTo('GET', _comparison), hasLength(1)); // price not reloaded
    expect(find.text(formatPrice(139)), findsOneWidget);
  });
}
