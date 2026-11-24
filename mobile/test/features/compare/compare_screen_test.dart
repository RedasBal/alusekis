import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/compare/compare_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/products/1/prices';

Map<String, Object> _offer(int id, int storeId, String store, String address, int cents) => {
      'priceEntryId': id,
      'storeId': storeId,
      'storeName': store,
      'storeAddress': address,
      'priceCents': cents,
      'observedAt': '2026-11-20T10:30:00Z', // 12:30 in Vilnius
      'isStale': false,
    };

Map<String, Object> _comparison(List<Object> offers) => {
      'product': {'id': 1, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'items': offers,
      'storeCount': offers.length,
      'singleStore': offers.length == 1,
    };

final _lidl = _offer(1, 4, 'Lidl', 'Kalvarijų g. 202', 139);
final _maxima = _offer(2, 1, 'Maxima XX', 'Ukmergės g. 282', 149);
final _iki = _offer(3, 2, 'Iki', 'Žirmūnų g. 64', 199);

Future<void> _pump(WidgetTester tester, FakeApiAdapter adapter) async {
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
        home: ProductCompareScreen(productId: 1, productName: 'Švyturys Ekstra', volumeMl: 500),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Vertical order of the stores on screen, top first.
List<String> _storeOrder(WidgetTester tester, List<String> names) {
  final present = names.where((n) => find.text(n).evaluate().isNotEmpty).toList();
  present.sort(
    (a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy),
  );
  return present;
}

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('shows the product, the explanation and each store with its price and date',
      (tester) async {
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima]));

    await _pump(tester, adapter);

    expect(find.text('Kainų palyginimas'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml · Švyturys'), findsOneWidget);
    expect(find.text('Kaina – vienos pakuotės kaina be užstato'), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text('Kalvarijų g. 202'), findsOneWidget);
    expect(find.text(formatPrice(139)), findsOneWidget);
    expect(find.text('Maxima XX'), findsOneWidget);
    expect(find.text('Ukmergės g. 282'), findsOneWidget);
    expect(find.text(formatPrice(149)), findsOneWidget);
    expect(find.text('Patikrinta: 2026-11-20 12:30'), findsNWidgets(2));
  });

  testWidgets('shows how much dearer each store is than the cheapest, in cents',
      (tester) async {
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima, _iki]));

    await _pump(tester, adapter);

    // 1,49 - 1,39 = 0,10 and 1,99 - 1,39 = 0,60; the cheapest has no extra line.
    expect(find.text('+${formatPrice(10)} brangiau'), findsOneWidget);
    expect(find.text('+${formatPrice(60)} brangiau'), findsOneWidget);
    expect(find.textContaining('brangiau'), findsNWidgets(2));
  });

  testWidgets('starts cheapest first and asks the server for that order', (tester) async {
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima, _iki]));

    await _pump(tester, adapter);

    expect(adapter.requestsTo('GET', _path).single.queryParameters, {'sort': 'asc'});
    expect(_storeOrder(tester, ['Lidl', 'Maxima XX', 'Iki']), ['Lidl', 'Maxima XX', 'Iki']);
    expect(find.text('Pigiausia pirmiausia'), findsOneWidget);
    expect(find.text('Brangiausia pirmiausia'), findsOneWidget);
  });

  testWidgets('switching to dearest first reloads in that order', (tester) async {
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima, _iki]));
    adapter.reply('GET', _path, body: _comparison([_iki, _maxima, _lidl]));
    await _pump(tester, adapter);

    await tester.tap(find.text('Brangiausia pirmiausia'));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path).last.queryParameters, {'sort': 'desc'});
    expect(_storeOrder(tester, ['Lidl', 'Maxima XX', 'Iki']), ['Iki', 'Maxima XX', 'Lidl']);
    // The difference is from the cheapest price whatever the order.
    expect(find.text('+${formatPrice(60)} brangiau'), findsOneWidget);

    // And back again.
    adapter.replace('GET', _path, body: _comparison([_lidl, _maxima, _iki]));
    await tester.tap(find.text('Pigiausia pirmiausia'));
    await tester.pumpAndSettle();
    expect(adapter.requestsTo('GET', _path).last.queryParameters, {'sort': 'asc'});
    expect(_storeOrder(tester, ['Lidl', 'Maxima XX', 'Iki']), ['Lidl', 'Maxima XX', 'Iki']);
  });

  testWidgets('choosing the order already shown sends nothing new', (tester) async {
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima]));
    await _pump(tester, adapter);

    await tester.tap(find.text('Pigiausia pirmiausia'));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path), hasLength(1));
  });

  testWidgets('an error is explained without technical details and can be retried',
      (tester) async {
    adapter.replyError('GET', _path, 500, 'internal_error');
    adapter.reply('GET', _path, body: _comparison([_lidl, _maxima]));

    await _pump(tester, adapter);

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('internal_error'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(find.text('Lidl'), findsNothing);

    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();

    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });
}
