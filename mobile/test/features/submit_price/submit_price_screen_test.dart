import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/submit_price/submit_price_models.dart';
import 'package:alusekis/features/submit_price/submit_price_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/prices';

const _target = SubmitPriceTarget(
  productId: 7,
  productName: 'Švyturys Ekstra',
  volumeMl: 500,
  storeId: 3,
  storeName: 'Maxima XX',
  currentPriceCents: 149,
);

Map<String, Object> _saved(int cents, {bool large = false}) => {
      'id': 61,
      'productId': 7,
      'storeId': 3,
      'priceCents': cents,
      'observedAt': '2026-11-24T10:30:00Z',
      'isLargeChange': large,
    };

Map<String, Object> _largeChange(int previous) => {
      'code': 'large_price_change',
      'message': 'server text',
      'requestId': 'r-1',
      'previousPriceCents': previous,
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
      jsonEncode(_saved(199)),
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
                MaterialPageRoute(builder: (_) => const SubmitPriceScreen(target: _target)),
              );
              onResult(result);
            },
            child: const Text('Atidaryti'),
          ),
        ),
      );
}

/// Pumps the app with the form open; returns a getter for what the form popped with.
Future<Object? Function()> _openForm(WidgetTester tester, HttpClientAdapter adapter) async {
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

Future<void> _enterAndConfirm(WidgetTester tester, String price) async {
  await tester.enterText(find.byType(TextField), price);
  await tester.tap(find.widgetWithText(FilledButton, 'Patvirtinti'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _body(RequestOptions request) => request.data as Map<String, dynamic>;

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('shows the product, the store and the current price; nothing is sent before "Patvirtinti"',
      (tester) async {
    await _openForm(tester, adapter);

    expect(find.text('Atnaujinti kainą'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.text('Maxima XX'), findsOneWidget);
    expect(find.text('Dabartinė kaina: ${formatPrice(149)}'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1,99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(adapter.requests, isEmpty);
  });

  testWidgets('wrong input is explained next to the field and not sent', (tester) async {
    await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '');
    expect(find.text('Įveskite kainą.'), findsOneWidget);

    await _enterAndConfirm(tester, '0');
    expect(find.text('Kaina turi būti nuo 0,01 iki 500,00 €.'), findsOneWidget);

    await _enterAndConfirm(tester, '500,01');
    expect(find.text('Kaina turi būti nuo 0,01 iki 500,00 €.'), findsOneWidget);

    await _enterAndConfirm(tester, '1,999');
    expect(find.text('Neteisingas kainos formatas. Pavyzdžiui, 1,99.'), findsOneWidget);

    expect(adapter.requests, isEmpty);
  });

  testWidgets('a saved price is confirmed only after the server answers, then the form closes',
      (tester) async {
    adapter.reply('POST', _path, status: 201, body: _saved(199));
    final result = await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '1.99'); // a point works as well as a comma

    final sent = _body(adapter.requestsTo('POST', _path).single);
    expect(sent['productId'], 7);
    expect(sent['storeId'], 3);
    expect(sent['priceCents'], 199);
    expect(sent['confirmLargeChange'], false);
    expect(sent['idempotencyKey'], isA<String>());
    expect((sent['idempotencyKey'] as String).length, 36);

    expect(result(), true);
    expect(find.text('Kaina išsaugota: ${formatPrice(199)}'), findsOneWidget);
  });

  testWidgets('a large change asks for confirmation and resends the same request confirmed',
      (tester) async {
    adapter.reply('POST', _path, status: 409, body: _largeChange(100));
    adapter.reply('POST', _path, status: 201, body: _saved(300, large: true));
    final result = await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '3');

    expect(
      find.text(
        'Kaina skiriasi nuo ankstesnės (buvo ${formatPrice(100)}, dabar ${formatPrice(300)}). '
        'Ar tikrai norite išsaugoti?',
      ),
      findsOneWidget,
    );
    expect(result(), 'not popped'); // nothing saved yet

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Patvirtinti')));
    await tester.pumpAndSettle();

    final requests = adapter.requestsTo('POST', _path);
    expect(requests, hasLength(2));
    expect(_body(requests[1])['confirmLargeChange'], true);
    expect(_body(requests[1])['priceCents'], 300);
    expect(_body(requests[1])['idempotencyKey'], _body(requests[0])['idempotencyKey']);
    expect(result(), true);
  });

  testWidgets('cancelling the large change sends nothing more and saves nothing', (tester) async {
    adapter.reply('POST', _path, status: 409, body: _largeChange(100));
    final result = await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '3');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Atšaukti')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(adapter.requestsTo('POST', _path), hasLength(1));
    expect(result(), 'not popped');
    expect(find.textContaining('Kaina išsaugota'), findsNothing);
  });

  testWidgets('a lost connection fails clearly; the retry reuses the same key', (tester) async {
    adapter.replaceWithOffline('POST', _path);
    final result = await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '1,99');

    expect(find.text('Nepavyko išsaugoti: nėra ryšio su serveriu. Kaina neišsaugota.'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(find.textContaining('Kaina išsaugota'), findsNothing);
    expect(result(), 'not popped');

    adapter.replace('POST', _path, status: 201, body: _saved(199));
    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();

    final requests = adapter.requestsTo('POST', _path);
    expect(requests, hasLength(2));
    expect(_body(requests[1])['idempotencyKey'], _body(requests[0])['idempotencyKey']);
    expect(result(), true);
  });

  testWidgets('a different price after a failure gets a new key', (tester) async {
    adapter.replaceWithOffline('POST', _path);
    await _openForm(tester, adapter);
    await _enterAndConfirm(tester, '1,99');

    adapter.replace('POST', _path, status: 201, body: _saved(249));
    await _enterAndConfirm(tester, '2,49');

    final requests = adapter.requestsTo('POST', _path);
    expect(requests, hasLength(2));
    expect(_body(requests[1])['idempotencyKey'], isNot(_body(requests[0])['idempotencyKey']));
  });

  testWidgets('a server error is shown without technical details', (tester) async {
    adapter.reply(
      'POST',
      _path,
      status: 500,
      body: {'code': 'internal_error', 'message': 'NullReferenceException', 'requestId': 'r'},
    );
    await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '1,99');

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('NullReference'), findsNothing);
    expect(find.textContaining('internal_error'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
  });

  testWidgets('a price the server rejects is explained next to the field', (tester) async {
    adapter.replyError('POST', _path, 422, 'price_invalid');
    await _openForm(tester, adapter);

    await _enterAndConfirm(tester, '1,99');

    expect(find.text('Kaina turi būti nuo 0,01 iki 500,00 €.'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });

  testWidgets('a double tap sends once; after a second the button shows progress and stays disabled',
      (tester) async {
    final holding = _HoldingAdapter();
    final result = await _openForm(tester, holding);

    await tester.enterText(find.byType(TextField), '1,99');
    final confirm = find.widgetWithText(FilledButton, 'Patvirtinti');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false); // the second tap of a double tap
    await tester.pump();

    FilledButton button() => tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull); // disabled at once

    await tester.pump(const Duration(milliseconds: 500));
    expect(holding.requests, hasLength(1)); // the second tap sent nothing
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
