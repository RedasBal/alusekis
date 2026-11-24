import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/core/utils/price_format.dart';
import 'package:alusekis/features/report/report_models.dart';
import 'package:alusekis/features/report/report_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _path = '/api/v1/reports';

final _target = ReportTarget(
  priceEntryId: 11,
  productName: 'Švyturys Ekstra',
  volumeMl: 500,
  storeName: 'Maxima XX',
  priceCents: 149,
  observedAt: DateTime.utc(2026, 11, 22, 10, 30),
);

Map<String, Object> _stored() => {
      'reportId': 5,
      'status': 'New',
      'submittedAt': '2026-11-24T10:30:00Z',
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
      jsonEncode(_stored()),
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
  const _Launcher({required this.target, required this.onResult});

  final ReportTarget target;
  final void Function(Object? result) onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => ReportScreen(target: target)),
              );
              onResult(result);
            },
            child: const Text('Atidaryti'),
          ),
        ),
      );
}

Future<Object? Function()> _openForm(WidgetTester tester, HttpClientAdapter adapter) async {
  tester.view.physicalSize = const Size(800, 2400);
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
      child: MaterialApp(home: _Launcher(target: _target, onResult: (r) => result = r)),
    ),
  );
  await tester.tap(find.text('Atidaryti'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _choose(WidgetTester tester, ReportReason reason) async {
  await tester.tap(find.text(reason.label));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Pateikti'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _body(RequestOptions request) => request.data as Map<String, dynamic>;

void main() {
  late FakeApiAdapter adapter;

  setUp(() => adapter = FakeApiAdapter());

  group('checkReportInput', () {
    test('a reason is required', () {
      final input = checkReportInput(null, '');
      expect(input.isValid, isFalse);
      expect(input.reasonError, 'Pasirinkite priežastį.');
    });

    test('"Kita" needs a comment, spaces do not count', () {
      expect(checkReportInput(ReportReason.other, '').commentError, isNotNull);
      expect(checkReportInput(ReportReason.other, '    ').commentError, isNotNull);
      expect(checkReportInput(ReportReason.other, ' kažkas ').comment, 'kažkas');
    });

    test('the other reasons need no comment', () {
      for (final reason in [
        ReportReason.wrongPrice,
        ReportReason.differentProduct,
        ReportReason.outdatedData,
      ]) {
        final input = checkReportInput(reason, '');
        expect(input.isValid, isTrue);
        expect(input.comment, isNull);
      }
    });

    test('500 characters are fine, 501 are not', () {
      expect(checkReportInput(ReportReason.wrongPrice, 'a' * 500).isValid, isTrue);
      expect(
        checkReportInput(ReportReason.wrongPrice, 'a' * 501).commentError,
        'Komentaras negali būti ilgesnis nei 500 simbolių.',
      );
    });
  });

  testWidgets('shows the price as context and marks the required fields before any input',
      (tester) async {
    await _openForm(tester, adapter);

    expect(find.text('Pranešti apie klaidą'), findsOneWidget);
    expect(find.text('Švyturys Ekstra'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.text('Maxima XX'), findsOneWidget);
    expect(find.text(formatPrice(149)), findsOneWidget);
    expect(find.textContaining('Patikrinta:'), findsOneWidget);

    expect(find.text('Laukai, pažymėti *, yra privalomi.'), findsOneWidget);
    expect(find.text('Priežastis *'), findsOneWidget);
    for (final reason in ReportReason.values) {
      expect(find.text(reason.label), findsOneWidget);
    }
    expect(find.text('Komentaras (neprivalomas)'), findsOneWidget);
    expect(find.textContaining('nekeičia kainos'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('choosing "Kita" marks the comment as required', (tester) async {
    await _openForm(tester, adapter);

    await _choose(tester, ReportReason.other);

    expect(find.text('Komentaras *'), findsOneWidget);
    expect(find.text('Komentaras (neprivalomas)'), findsNothing);
  });

  testWidgets('no reason: the error is next to the options, nothing is sent', (tester) async {
    await _openForm(tester, adapter);

    await _submit(tester);

    expect(find.text('Pasirinkite priežastį.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('"Kita" without a comment is explained next to the field and not sent', (tester) async {
    await _openForm(tester, adapter);

    await _choose(tester, ReportReason.other);
    await _submit(tester);

    expect(find.text('Aprašykite problemą, kai pasirenkate „Kita“.'), findsOneWidget);
    expect(adapter.requests, isEmpty);

    await tester.enterText(find.byType(TextField), '     ');
    await _submit(tester);
    expect(find.text('Aprašykite problemą, kai pasirenkate „Kita“.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('a comment over 500 characters is refused, with a counter, and not sent', (tester) async {
    await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await tester.enterText(find.byType(TextField), 'a' * 501);
    await tester.pumpAndSettle();
    expect(find.text('501/500'), findsOneWidget); // the counter

    await _submit(tester);

    expect(find.text('Komentaras negali būti ilgesnis nei 500 simbolių.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('a comment of exactly 500 characters is sent', (tester) async {
    adapter.reply('POST', _path, status: 201, body: _stored());
    await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await tester.enterText(find.byType(TextField), 'a' * 500);
    await _submit(tester);

    expect((_body(adapter.requestsTo('POST', _path).single)['comment'] as String).length, 500);
  });

  testWidgets('success is shown only after the server answers, explains what happens, then closes',
      (tester) async {
    adapter.reply('POST', _path, status: 201, body: _stored());
    final result = await _openForm(tester, adapter);

    await _choose(tester, ReportReason.differentProduct);
    await tester.enterText(find.byType(TextField), '  Tai kitas alus  ');
    await _submit(tester);

    final sent = _body(adapter.requestsTo('POST', _path).single);
    expect(sent['priceEntryId'], 11);
    expect(sent['reason'], 'DifferentProduct');
    expect(sent['comment'], 'Tai kitas alus'); // trimmed
    expect((sent['idempotencyKey'] as String).length, 36);

    expect(result(), true);
    expect(find.text(reportSentMessage), findsOneWidget);
    expect(find.textContaining('Pranešimas pateiktas'), findsOneWidget);
    expect(find.textContaining('nebus pakeista iškart'), findsOneWidget);
  });

  testWidgets('every reason is sent under its own name, an empty comment is left out', (tester) async {
    const names = {
      ReportReason.wrongPrice: 'WrongPrice',
      ReportReason.differentProduct: 'DifferentProduct',
      ReportReason.outdatedData: 'OutdatedData',
    };
    for (final entry in names.entries) {
      adapter = FakeApiAdapter();
      adapter.reply('POST', _path, status: 201, body: _stored());
      await _openForm(tester, adapter);

      await _choose(tester, entry.key);
      await _submit(tester);

      final sent = _body(adapter.requestsTo('POST', _path).single);
      expect(sent['reason'], entry.value);
      expect(sent.containsKey('comment'), isFalse);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('"Atšaukti" closes the form and sends nothing', (tester) async {
    final result = await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Atšaukti'));
    await tester.pumpAndSettle();

    expect(result(), false);
    expect(adapter.requests, isEmpty);
    expect(find.textContaining('Pranešimas pateiktas'), findsNothing);
  });

  testWidgets('a lost connection fails clearly; the retry reuses the same key', (tester) async {
    adapter.replaceWithOffline('POST', _path);
    final result = await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await _submit(tester);

    expect(
      find.text('Nepavyko pateikti: nėra ryšio su serveriu. Pranešimas nepateiktas.'),
      findsOneWidget,
    );
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(find.textContaining('Pranešimas pateiktas'), findsNothing);
    expect(result(), 'not popped');

    adapter.replace('POST', _path, status: 201, body: _stored());
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
    final result = await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await _submit(tester);

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('NullReference'), findsNothing);
    expect(find.textContaining('internal_error'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
    expect(find.textContaining('Pranešimas pateiktas'), findsNothing);
    expect(result(), 'not popped');
  });

  testWidgets('a price entry that is gone is explained, no retry is offered', (tester) async {
    adapter.replyError('POST', _path, 404, 'not_found');
    await _openForm(tester, adapter);

    await _choose(tester, ReportReason.wrongPrice);
    await _submit(tester);

    expect(find.text('Nieko nerasta.'), findsOneWidget);
    expect(find.text('Bandyti dar kartą'), findsNothing);
  });

  testWidgets('a double tap sends once; after a second the button shows progress and stays disabled',
      (tester) async {
    final holding = _HoldingAdapter();
    final result = await _openForm(tester, holding);

    await _choose(tester, ReportReason.wrongPrice);
    final submit = find.widgetWithText(FilledButton, 'Pateikti');
    await tester.tap(submit);
    await tester.tap(submit, warnIfMissed: false); // the second tap of a double tap
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
