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

Map<String, Object> _offer(
  int id,
  int storeId,
  String store,
  int cents, {
  bool stale = false,
}) =>
    {
      'priceEntryId': id,
      'storeId': storeId,
      'storeName': store,
      'storeAddress': 'Gatvė $storeId',
      'priceCents': cents,
      'observedAt': '2026-11-20T10:30:00Z',
      'isStale': stale,
    };

Map<String, Object> _comparison(List<Object> offers) => {
      'product': {'id': 1, 'name': 'Švyturys Ekstra', 'brand': 'Švyturys', 'volumeMl': 500},
      'items': offers,
      'storeCount': offers.length,
      'singleStore': offers.length == 1,
    };

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
      child: const MaterialApp(home: ProductCompareScreen(productId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('a product without prices says so, and offers nothing to sort', (tester) async {
    adapter.reply('GET', _path, body: _comparison([]));

    await _pump(tester, adapter);

    expect(find.text('Šiam produktui kainų kol kas nėra'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget); // the product is still named
    expect(find.text('Pigiausia pirmiausia'), findsNothing);
    expect(find.text('Brangiausia pirmiausia'), findsNothing);
    expect(find.text('Palyginimui trūksta kitų parduotuvių duomenų'), findsNothing);
  });

  testWidgets('one store: the price is shown with a note that others are missing',
      (tester) async {
    adapter.reply('GET', _path, body: _comparison([_offer(1, 4, 'Lidl', 139)]));

    await _pump(tester, adapter);

    expect(find.text('Palyginimui trūksta kitų parduotuvių duomenų'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget); // text and icon, not colour
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text(formatPrice(139)), findsOneWidget);
    // Nothing to compare: no "cheapest" label and no ordering to choose.
    expect(find.text('Pigiausia'), findsNothing);
    expect(find.text('Pigiausia pirmiausia'), findsNothing);
    expect(find.textContaining('brangiau'), findsNothing);
  });

  testWidgets('a stale price is marked with text and an icon, a fresh one is not',
      (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _comparison([
        _offer(1, 4, 'Lidl', 139),
        _offer(2, 1, 'Maxima XX', 149, stale: true),
      ]),
    );

    await _pump(tester, adapter);

    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('only the cheapest store is labelled "Pigiausia", whatever the order',
      (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _comparison([
        _offer(2, 1, 'Maxima XX', 149),
        _offer(3, 2, 'Iki', 199),
        _offer(1, 4, 'Lidl', 139), // cheapest, listed last (dearest first)
      ]),
    );

    await _pump(tester, adapter);

    expect(find.text('Pigiausia'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    // The label sits with the last row (Lidl), not with the first.
    final label = tester.getTopLeft(find.text('Pigiausia')).dy;
    expect(label, greaterThan(tester.getTopLeft(find.text('Maxima XX')).dy));
    expect(label, greaterThan(tester.getTopLeft(find.text('Iki')).dy));
    // The others say how much dearer they are; the cheapest does not.
    expect(find.text('+${formatPrice(10)} brangiau'), findsOneWidget);
    expect(find.text('+${formatPrice(60)} brangiau'), findsOneWidget);
    expect(find.textContaining('brangiau'), findsNWidgets(2));
  });

  testWidgets('stores tied for the lowest price are all labelled', (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _comparison([
        _offer(1, 1, 'Lidl', 139),
        _offer(2, 2, 'Iki', 139),
        _offer(3, 3, 'Maxima XX', 149),
      ]),
    );

    await _pump(tester, adapter);

    expect(find.text('Pigiausia'), findsNWidgets(2));
  });

  testWidgets('when every price is the same nothing is called cheapest', (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _comparison([_offer(1, 1, 'Lidl', 139), _offer(2, 2, 'Iki', 139)]),
    );

    await _pump(tester, adapter);

    expect(find.text('Pigiausia'), findsNothing);
    expect(find.textContaining('brangiau'), findsNothing);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text('Iki'), findsOneWidget);
  });
}
