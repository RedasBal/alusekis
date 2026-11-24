import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/clock.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/stores/store_prices_cache.dart';
import 'package:alusekis/features/stores/store_prices_models.dart';
import 'package:alusekis/features/stores/store_prices_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/stores/1/prices';

/// "Now" in every test: 2026-11-23 12:00 UTC.
final _now = DateTime.utc(2026, 11, 23, 12);

late FakeApiAdapter _adapter;
late AppPreferences _prefs;

Map<String, Object> _priceJson(
  int id,
  String name,
  int volumeMl,
  int cents,
  String observedAt, {
  bool stale = false,
}) =>
    {
      'priceEntryId': id,
      'productId': id,
      'productName': name,
      'volumeMl': volumeMl,
      'priceCents': cents,
      'observedAt': observedAt,
      'isStale': stale,
    };

Map<String, Object> _pageJson(List<Object> items, {int? total, int page = 1}) => {
      'store': {'id': 1, 'name': 'Maxima XX', 'address': 'Ukmergės g. 282'},
      'items': items,
      'total': total ?? items.length,
      'page': page,
      'pageSize': 20,
    };

Future<void> _pump(
  WidgetTester tester, {
  Future<void> Function(AppPreferences prefs)? beforeStart,
}) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  _prefs = AppPreferences(await SharedPreferences.getInstance());
  await beforeStart?.call(_prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(_prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        httpClientAdapterProvider.overrideWithValue(_adapter),
        nowProvider.overrideWithValue(() => _now),
      ],
      child: const MaterialApp(
        home: StorePricesScreen(storeId: 1, storeName: 'Maxima XX'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _adapter = FakeApiAdapter());

  testWidgets('shows product, volume, price and the check date in Vilnius time',
      (tester) async {
    _adapter.reply(
      'GET',
      _path,
      body: _pageJson([
        _priceJson(1, 'Švyturys Ekstra', 500, 149, '2026-11-22T10:30:00Z'),
        _priceJson(2, 'Utenos Originalus', 1000, 209, '2026-11-22T08:00:00Z'),
      ]),
    );

    await _pump(tester);

    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    // formatPrice uses a non-breaking space before the euro sign.
    expect(find.text(formatPrice(149)), findsOneWidget);
    expect(find.text(formatPrice(209)), findsOneWidget);
    expect(formatPrice(149), startsWith('1,49'));
    // 10:30 UTC is 12:30 in Vilnius in winter.
    expect(find.text('Patikrinta: 2026-11-22 12:30'), findsOneWidget);
    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsNothing);
  });

  testWidgets('a stale price is marked with text, a fresh one is not',
      (tester) async {
    _adapter.reply(
      'GET',
      _path,
      body: _pageJson([
        _priceJson(1, 'Švyturys Ekstra', 500, 149, '2026-11-22T10:30:00Z'),
        _priceJson(2, 'Kalnapilis', 500, 125, '2026-11-10T10:30:00Z', stale: true),
      ]),
    );

    await _pump(tester);

    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('a store without prices shows the empty message', (tester) async {
    _adapter.reply('GET', _path, body: _pageJson([]));

    await _pump(tester);

    expect(find.text('Šioje parduotuvėje kainų kol kas nėra'), findsOneWidget);
  });

  testWidgets('a server error without saved data is explained with a retry',
      (tester) async {
    _adapter.replyError('GET', _path, 500, 'internal_error');

    await _pump(tester);

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('500'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);

    // The retry asks the server again and shows the data.
    _adapter.replace(
      'GET',
      _path,
      body: _pageJson([_priceJson(1, 'Heineken', 500, 159, '2026-11-22T10:30:00Z')]),
    );
    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();
    expect(find.text('Heineken'), findsOneWidget);
  });

  testWidgets('offline without saved data says the connection is missing',
      (tester) async {
    _adapter.replaceWithOffline('GET', _path);

    await _pump(tester);

    expect(find.textContaining('Nėra ryšio su serveriu'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
  });

  testWidgets('a successful answer is saved on the device', (tester) async {
    _adapter.reply(
      'GET',
      _path,
      body: _pageJson([_priceJson(1, 'Heineken', 500, 159, '2026-11-22T10:30:00Z')]),
    );

    await _pump(tester);

    final saved = StorePricesCache(_prefs).read(1)!;
    expect(saved.items.single.productName, 'Heineken');
    expect(saved.syncedAt, _now);
  });

  testWidgets('offline with saved data shows them and when they were synced',
      (tester) async {
    _adapter.replaceWithOffline('GET', _path);

    await _pump(
      tester,
      beforeStart: (prefs) => StorePricesCache(prefs).write(
        1,
        PricesSnapshot(
          store: const StoreSummary(id: 1, name: 'Maxima XX', address: 'Ukmergės g. 282'),
          items: [
            StorePrice(
              priceEntryId: 1,
              productId: 1,
              productName: 'Švyturys Ekstra',
              volumeMl: 500,
              priceCents: 149,
              observedAt: DateTime.utc(2026, 11, 10, 10, 30), // 13 days before "now"
              isStale: false, // fresh when saved, but old by now
            ),
          ],
          total: 1,
          syncedAt: DateTime.utc(2026, 11, 20, 12, 30), // 14:30 in Vilnius
        ),
      ),
    );

    expect(
      find.text('Rodomi išsaugoti duomenys (sinchronizuota 2026-11-20 14:30)'),
      findsOneWidget,
    );
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text(formatPrice(149)), findsOneWidget);
    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsOneWidget);
    expect(find.textContaining('Nėra ryšio su serveriu'), findsNothing);
    expect(find.text('Rodyti daugiau'), findsNothing); // paging needs the server
  });

  testWidgets('"Rodyti daugiau" loads the next page and appends it',
      (tester) async {
    _adapter.reply(
      'GET',
      _path,
      body: _pageJson([_priceJson(1, 'Ąžuolas', 500, 100, '2026-11-22T10:30:00Z')], total: 2),
    );
    _adapter.reply(
      'GET',
      _path,
      body: _pageJson(
        [_priceJson(2, 'Biržų', 500, 120, '2026-11-22T10:30:00Z')],
        total: 2,
        page: 2,
      ),
    );

    await _pump(tester);
    expect(find.text('Ąžuolas'), findsOneWidget);
    expect(find.text('Biržų'), findsNothing);

    await tester.tap(find.text('Rodyti daugiau'));
    await tester.pumpAndSettle();

    expect(find.text('Ąžuolas'), findsOneWidget);
    expect(find.text('Biržų'), findsOneWidget);
    expect(find.text('Rodyti daugiau'), findsNothing);
    expect(
      _adapter.requestsTo('GET', _path).last.queryParameters,
      {'page': 2, 'pageSize': 20},
    );
  });
}
