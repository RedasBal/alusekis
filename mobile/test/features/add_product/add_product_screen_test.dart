import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/add_product/add_product_models.dart';
import 'package:alusekis/features/add_product/add_product_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/products';

const _target = AddProductTarget(storeId: 3, storeName: 'Maxima XX');

Map<String, Object> _created({int cents = 199, int volumeMl = 500, String name = 'Žalgiris'}) => {
      'product': {'id': 70, 'name': name, 'volumeMl': volumeMl},
      'price': {
        'id': 61,
        'productId': 70,
        'storeId': 3,
        'priceCents': cents,
        'observedAt': '2026-11-24T10:30:00Z',
        'isLargeChange': false,
      },
    };

Map<String, Object> _exists() => {
      'code': 'product_exists',
      'message': 'server text',
      'requestId': 'r-1',
      'existingProduct': {'id': 9, 'name': 'Žalgiris', 'volumeMl': 500},
    };

/// Holds every answer until [release]; then answers 201.
class _HoldingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Completer<void> release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    await release.future;
    return ResponseBody.fromString(
      jsonEncode(_created()),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Opens the form from a plain page, so the result it pops with can be checked.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.onResult});

  final void Function(Object? result) onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const AddProductScreen(target: _target)),
              );
              onResult(result);
            },
            child: const Text('Atidaryti'),
          ),
        ),
      );
}

Future<Object? Function()> _openForm(WidgetTester tester, HttpClientAdapter adapter) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  Object? result = 'not popped';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage('token')),
        httpClientAdapterProvider.overrideWithValue(adapter),
      ],
      child: MaterialApp(home: _Launcher(onResult: (r) => result = r)),
    ),
  );
  await tester.tap(find.text('Atidaryti'));
  await tester.pumpAndSettle();
  return () => result;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _fill(
  WidgetTester tester, {
  String name = 'Žalgiris',
  String volume = '500',
  String price = '1,99',
  bool litres = false,
}) async {
  await tester.enterText(_field('Pavadinimas *'), name);
  await tester.enterText(_field('Talpa *'), volume);
  if (litres) {
    await tester.tap(find.text('l'));
    await tester.pump();
  }
  await tester.enterText(_field('Kaina, € *'), price);
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Patvirtinti'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _body(RequestOptions request) => request.data as Map<String, dynamic>;

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('required fields are marked before typing, the store is shown, nothing is sent',
      (tester) async {
    await _openForm(tester, adapter);

    expect(find.text('Pridėti produktą'), findsOneWidget);
    expect(find.text('Laukai, pažymėti *, yra privalomi.'), findsOneWidget);
    expect(find.text('Pavadinimas *'), findsOneWidget);
    expect(find.text('Talpa *'), findsOneWidget);
    expect(find.text('Kaina, € *'), findsOneWidget);
    expect(find.text('Maxima XX'), findsOneWidget); // the prefilled store

    await tester.enterText(_field('Kaina, € *'), '1,99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(adapter.requests, isEmpty);
  });

  testWidgets('empty form: an error next to each field, nothing is sent', (tester) async {
    await _openForm(tester, adapter);

    await _confirm(tester);

    expect(find.text('Įveskite pavadinimą.'), findsOneWidget);
    expect(find.text('Įveskite talpą.'), findsOneWidget);
    expect(find.text('Įveskite kainą.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('wrong values are explained next to their fields and not sent', (tester) async {
    await _openForm(tester, adapter);

    await _fill(tester, name: 'a', volume: '0', price: '500,01');
    await _confirm(tester);

    expect(find.text('Pavadinimas turi būti 2–150 simbolių.'), findsOneWidget);
    expect(find.text('Talpa turi būti nuo 1 iki 50 000 ml (50 l).'), findsOneWidget);
    expect(find.text('Kaina turi būti nuo 0,01 iki 500,00 €.'), findsOneWidget);

    await _fill(tester, name: 'Alus', volume: '500,5', price: '1,999');
    await _confirm(tester);

    expect(find.text('Talpa turi būti sveika ml reikšmė.'), findsOneWidget);
    expect(find.text('Neteisingas kainos formatas. Pavyzdžiui, 1,99.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('success is shown only after the server answers, then the form closes', (tester) async {
    adapter.reply('POST', _path, status: 201, body: _created());
    final result = await _openForm(tester, adapter);

    await _fill(tester, name: '  Žalgiris ', volume: '500', price: '1.99'); // a point works too
    await _confirm(tester);

    final sent = _body(adapter.requestsTo('POST', _path).single);
    expect(sent['name'], 'Žalgiris'); // trimmed
    expect(sent['volumeMl'], 500);
    expect(sent['storeId'], 3);
    expect(sent['priceCents'], 199);
    expect((sent['idempotencyKey'] as String).length, 36);

    expect(result(), true);
    expect(
      find.text('Produktas pridėtas: Žalgiris, 500 ml, ${formatPrice(199)}'),
      findsOneWidget,
    );
  });

  testWidgets('litres are converted to whole millilitres before sending', (tester) async {
    adapter.reply('POST', _path, status: 201, body: _created(volumeMl: 500));
    await _openForm(tester, adapter);

    await _fill(tester, volume: '0,5', litres: true);
    await _confirm(tester);

    expect(_body(adapter.requestsTo('POST', _path).single)['volumeMl'], 500);
  });

  testWidgets('0,0005 l is rejected on the phone, nothing is sent', (tester) async {
    await _openForm(tester, adapter);

    await _fill(tester, volume: '0,0005', litres: true);
    await _confirm(tester);

    expect(find.text('Talpa turi būti sveika ml reikšmė.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('a duplicate opens the dialog; "Atšaukti" closes it and saves nothing', (tester) async {
    adapter.reply('POST', _path, status: 409, body: _exists());
    final result = await _openForm(tester, adapter);

    await _fill(tester, name: '  ŽALGIRIS ');
    await _confirm(tester);

    expect(
      find.text('Toks produktas jau yra: Žalgiris, 500 ml. Norite atnaujinti jo kainą?'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Atnaujinti kainą'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Atšaukti')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(adapter.requestsTo('POST', _path), hasLength(1));
    expect(result(), 'not popped');
    expect(find.textContaining('Produktas pridėtas'), findsNothing);
  });

  testWidgets('a lost connection fails clearly; the retry reuses the same key', (tester) async {
    adapter.replaceWithOffline('POST', _path);
    final result = await _openForm(tester, adapter);

    await _fill(tester);
    await _confirm(tester);

    expect(
      find.text('Nepavyko išsaugoti: nėra ryšio su serveriu. Produktas nepridėtas.'),
      findsOneWidget,
    );
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(find.textContaining('Produktas pridėtas'), findsNothing);
    expect(result(), 'not popped');

    adapter.replace('POST', _path, status: 201, body: _created());
    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();

    final requests = adapter.requestsTo('POST', _path);
    expect(requests, hasLength(2));
    expect(_body(requests[1])['idempotencyKey'], _body(requests[0])['idempotencyKey']);
    expect(result(), true);
  });

  testWidgets('a server error is shown without technical details', (tester) async {
    adapter.reply(
      'POST',
      _path,
      status: 500,
      body: {'code': 'internal_error', 'message': 'NullReferenceException', 'requestId': 'r'},
    );
    await _openForm(tester, adapter);

    await _fill(tester);
    await _confirm(tester);

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('NullReference'), findsNothing);
    expect(find.textContaining('internal_error'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
  });

  testWidgets('a price the server rejects is explained next to the price field', (tester) async {
    adapter.replyError('POST', _path, 422, 'price_invalid');
    await _openForm(tester, adapter);

    await _fill(tester);
    await _confirm(tester);

    expect(find.text('Kaina turi būti nuo 0,01 iki 500,00 €.'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });

  testWidgets('a double tap sends once; after a second the button shows progress and stays disabled',
      (tester) async {
    final holding = _HoldingAdapter();
    final result = await _openForm(tester, holding);

    await _fill(tester);
    final confirm = find.widgetWithText(FilledButton, 'Patvirtinti');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false); // the second tap of a double tap
    await tester.pump();

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull); // disabled at once

    await tester.pump(const Duration(milliseconds: 500));
    expect(holding.requests, hasLength(1));
    expect(find.text('Siunčiama…'), findsNothing); // not before a second

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Siunčiama…'), findsOneWidget);
    expect(button().onPressed, isNull);
    expect(result(), 'not popped');

    holding.release.complete();
    await tester.pumpAndSettle();

    expect(holding.requests, hasLength(1));
    expect(result(), true);
  });
}
