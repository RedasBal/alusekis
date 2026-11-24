import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/search/search_query.dart';
import 'package:alusekis/features/search/search_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/products/search';

Map<String, Object> _product(
  int id,
  String name, {
  int volumeMl = 500,
  String? brand,
  Map<String, Object>? lowestPrice,
}) =>
    {
      'id': id,
      'name': name,
      'volumeMl': volumeMl,
      'brand': ?brand,
      'lowestPrice': ?lowestPrice,
    };

Map<String, Object> _lowest(int cents, String store, {bool stale = false}) => {
      'priceCents': cents,
      'storeId': 1,
      'storeName': store,
      'observedAt': '2026-11-20T10:30:00Z',
      'isStale': stale,
    };

Map<String, Object> _items(List<Object> items) => {'items': items};

/// Answers every request as if there were no connection.
class _OfflineAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException.connectionError(requestOptions: options, reason: 'offline');
  }

  @override
  void close({bool force = false}) {}
}

/// Holds the answer to the query "ab" until [release] is called; every other
/// query is answered at once.
class _SlowFirstAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Completer<void> release = Completer<void>();

  ResponseBody _json(Object body) => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.queryParameters['q'] == 'ab') {
      await release.future;
      return _json(_items([_product(1, 'Senas rezultatas')]));
    }
    return _json(_items([_product(2, 'Naujas rezultatas')]));
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, HttpClientAdapter adapter) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        httpClientAdapterProvider.overrideWithValue(adapter),
      ],
      child: const MaterialApp(home: SearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

/// Lets the debounce pass and the answer arrive.
Future<void> _search(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.pump(searchDebounce + const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  testWidgets('starts with the hint and sends nothing', (tester) async {
    await _pump(tester, adapter);

    expect(find.text('Įveskite bent 2 simbolius'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('under 2 characters is never sent; the hint stays', (tester) async {
    await _pump(tester, adapter);

    await _search(tester, 'a');
    expect(find.text('Įveskite bent 2 simbolius'), findsOneWidget);

    await _search(tester, '   ');
    await _search(tester, ' a ');
    expect(find.text('Įveskite bent 2 simbolius'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('shows product, volume, brand, lowest price and store',
      (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _items([
        _product(1, 'Švyturys Ekstra', brand: 'Švyturys', lowestPrice: _lowest(139, 'Lidl')),
        _product(2, 'Švyturys Baltijos', volumeMl: 330),
      ]),
    );
    await _pump(tester, adapter);

    await _search(tester, '  švyturys  ');

    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml · Švyturys'), findsOneWidget);
    expect(find.text(formatPrice(139)), findsOneWidget);
    expect(find.text('Lidl'), findsOneWidget);
    expect(find.text('Švyturys Baltijos'), findsOneWidget);
    expect(find.text('330 ml'), findsOneWidget);
    expect(find.text('Kainų kol kas nėra'), findsOneWidget);
    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsNothing);
    // The text is trimmed before it is sent.
    expect(adapter.requestsTo('GET', _path).single.queryParameters, {'q': 'švyturys'});
  });

  testWidgets('an old price is marked with text, not colour alone',
      (tester) async {
    adapter.reply(
      'GET',
      _path,
      body: _items([
        _product(1, 'Utenos Originalus', lowestPrice: _lowest(119, 'Iki', stale: true)),
      ]),
    );
    await _pump(tester, adapter);

    await _search(tester, 'utenos');

    expect(find.text('Neatnaujinta daugiau nei 7 dienas'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('waits for a pause in typing and sends only the last text',
      (tester) async {
    adapter.reply('GET', _path, body: _items([_product(1, 'Alus')]));
    await _pump(tester, adapter);

    await _type(tester, 'ab');
    await tester.pump(const Duration(milliseconds: 100));
    await _type(tester, 'abc');
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests, isEmpty); // still typing

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(adapter.requestsTo('GET', _path), hasLength(1));
    expect(adapter.requests.single.queryParameters, {'q': 'abc'});
  });

  testWidgets('a new text cancels the earlier request and its late answer is ignored',
      (tester) async {
    final slow = _SlowFirstAdapter();
    await _pump(tester, slow);

    // Request 1 is held, so the spinner keeps animating: pump, don't settle.
    await _type(tester, 'ab');
    await tester.pump(searchDebounce + const Duration(milliseconds: 10));
    await tester.pump();
    expect(slow.requests, hasLength(1));

    await _search(tester, 'abc'); // request 2 answers at once

    expect(find.text('Naujas rezultatas'), findsOneWidget);
    expect(slow.requests.first.cancelToken?.isCancelled, isTrue);

    slow.release.complete(); // the old answer finally arrives
    await tester.pumpAndSettle();

    expect(find.text('Naujas rezultatas'), findsOneWidget);
    expect(find.text('Senas rezultatas'), findsNothing);
  });

  testWidgets('no match says so and asks to change the query', (tester) async {
    adapter.reply('GET', _path, body: _items([]));
    await _pump(tester, adapter);

    await _search(tester, 'nera');

    expect(find.text('Nieko nerasta. Pakeiskite užklausą.'), findsOneWidget);
  });

  testWidgets('a server error is explained without technical details and can be retried',
      (tester) async {
    adapter.replyError('GET', _path, 500, 'internal_error');
    adapter.reply('GET', _path, body: _items([_product(1, 'Heineken')]));
    await _pump(tester, adapter);

    await _search(tester, 'heineken');

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('500'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);

    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();

    expect(find.text('Heineken'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });

  testWidgets('no connection gives a clear Lithuanian message with a retry',
      (tester) async {
    final offline = _OfflineAdapter();
    await _pump(tester, offline);

    await _search(tester, 'heineken');

    expect(find.textContaining('Nepavyko prisijungti prie serverio'), findsOneWidget);
    expect(find.textContaining('Dio'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(offline.calls, 1);

    await tester.tap(find.text('Bandyti dar kartą'));
    await tester.pumpAndSettle();
    expect(offline.calls, 2);
  });

  testWidgets('the clear button empties the field and brings back the hint',
      (tester) async {
    adapter.reply('GET', _path, body: _items([_product(1, 'Heineken')]));
    await _pump(tester, adapter);
    await _search(tester, 'heineken');
    expect(find.text('Heineken'), findsOneWidget);

    await tester.tap(find.byTooltip('Išvalyti'));
    await tester.pumpAndSettle();

    expect(find.text('Heineken'), findsNothing);
    expect(find.text('Įveskite bent 2 simbolius'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
}
