import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/features/stores/location_service.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:alusekis/features/stores/store_models.dart';
import 'package:alusekis/features/stores/stores_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _stores = '/api/v1/stores';

late FakeApiAdapter _adapter;

Future<void> _pumpApp(WidgetTester tester, FakeLocationService location) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
        httpClientAdapterProvider.overrideWithValue(_adapter),
        mapProviderProvider.overrideWithValue(const FakeMapProvider()),
        locationServiceProvider.overrideWithValue(location),
      ],
      child: const AlusekisApp(),
    ),
  );
  await tester.pumpAndSettle();
}

FakeLocationService _denied(LocationFailure why) =>
    FakeLocationService(LocationResult.failure(why));

void main() {
  setUp(() {
    _adapter = FakeApiAdapter();
    scriptStoreReplies(_adapter);
  });

  testWidgets('shows the saved city\'s stores on the map and in the list',
      (tester) async {
    await _pumpApp(tester, _denied(LocationFailure.denied));

    expect(find.text('FAKE-MAP'), findsOneWidget);
    expect(find.text('pin Iki'), findsOneWidget);

    await tester.tap(find.text('Sąrašas'));
    await tester.pumpAndSettle();
    expect(find.text('Ukmergės g. 282'), findsOneWidget);

    // Tapping a store shows its name and address.
    await tester.tap(find.text('Maxima XX'));
    await tester.pumpAndSettle();
    expect(find.text('Ukmergės g. 282, Vilnius'), findsOneWidget);
  });

  testWidgets('a refused location permission leaves the city search working',
      (tester) async {
    final location = _denied(LocationFailure.denied);
    await _pumpApp(tester, location);
    expect(location.calls, 0); // nothing is asked until the user taps

    await tester.tap(find.text('Naudoti vietą'));
    await tester.pumpAndSettle();

    expect(location.calls, 1);
    expect(find.textContaining('Vietos leidimas neduotas'), findsOneWidget);
    expect(find.text('pin Iki'), findsOneWidget); // the city's stores are still there
    expect(find.text('Miestas'), findsOneWidget);
  });

  testWidgets('with a position the nearby stores are shown with distances',
      (tester) async {
    final location = FakeLocationService(
      const LocationResult.success(GeoPoint(54.7, 25.2)),
    );
    await _pumpApp(tester, location);
    _adapter.replace(
      'GET',
      _stores,
      body: {
        'items': [storeJson(2, 'Maxima XX', 'Ukmergės g. 282', distanceKm: 3.66)],
      },
    );

    await tester.tap(find.text('Naudoti vietą'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sąrašas'));
    await tester.pumpAndSettle();

    final query = _adapter.requestsTo('GET', _stores).last.queryParameters;
    expect(query, {'lat': 54.7, 'lng': 25.2, 'radiusKm': 10});
    expect(find.text('3,7 km'), findsOneWidget);
  });

  testWidgets('no stores in the radius gives the empty message', (tester) async {
    final location = FakeLocationService(
      const LocationResult.success(GeoPoint(54.7, 25.2)),
    );
    await _pumpApp(tester, location);
    _adapter.replace('GET', _stores, body: {'items': <Object>[]});

    await tester.tap(find.text('Naudoti vietą'));
    await tester.pumpAndSettle();

    expect(find.text('Parduotuvių šiame spindulyje nerasta.'), findsOneWidget);
  });

  testWidgets('a server error is shown without technical details',
      (tester) async {
    await _pumpApp(tester, _denied(LocationFailure.denied));
    _adapter.replace(
      'GET',
      _stores,
      status: 500,
      body: {'code': 'internal_error', 'message': 'NullReference', 'requestId': 'r'},
    );

    final container =
        ProviderScope.containerOf(tester.element(find.byType(AlusekisApp)));
    container.read(storesControllerProvider.notifier).reload().ignore();
    await tester.pumpAndSettle();

    expect(find.textContaining('netikėta klaida'), findsOneWidget);
    expect(find.textContaining('500'), findsNothing);
    expect(find.text('Bandyti dar kartą'), findsOneWidget);
  });
}
