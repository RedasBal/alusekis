import 'package:alusekis/app.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<AppPreferences> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> stored = const {},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        // The real secure storage needs a platform plugin.
        sessionStorageProvider.overrideWithValue(InMemorySessionStorage()),
      ],
      child: const AlusekisApp(),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

const _ageQuestion = 'Ar jums yra 20 metų ar daugiau?';

void main() {
  group('age confirmation', () {
    testWidgets('is asked on first launch and "Taip" is remembered',
        (tester) async {
      final prefs = await _pumpApp(tester);

      expect(find.text(_ageQuestion), findsOneWidget);
      expect(prefs.ageConfirmed, isFalse);

      await tester.tap(find.text('Taip'));
      await tester.pumpAndSettle();

      expect(find.text(_ageQuestion), findsNothing);
      expect(find.text('Parduotuvių sąrašas bus čia.'), findsOneWidget);
      expect(prefs.ageConfirmed, isTrue);
    });

    testWidgets('is not asked again once confirmed', (tester) async {
      await _pumpApp(tester, stored: {'age_confirmed': true});

      expect(find.text(_ageQuestion), findsNothing);
      expect(find.text('Parduotuvių sąrašas bus čia.'), findsOneWidget);
    });

    testWidgets('"Ne" blocks price screens and explains why', (tester) async {
      final prefs = await _pumpApp(tester);

      await tester.tap(find.text('Ne'));
      await tester.pumpAndSettle();

      expect(prefs.ageConfirmed, isFalse);
      expect(find.text('Kainų informacija nepasiekiama'), findsOneWidget);
      expect(find.text('Parduotuvių sąrašas bus čia.'), findsNothing);

      await tester.tap(find.text('Paieška').last);
      await tester.pumpAndSettle();
      expect(find.text('Kainų informacija nepasiekiama'), findsOneWidget);
      expect(find.text('Produktų paieška bus čia.'), findsNothing);

      // The decision can be changed from the explanation.
      await tester.tap(find.text('Patvirtinti amžių'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taip'));
      await tester.pumpAndSettle();
      expect(find.text('Produktų paieška bus čia.'), findsOneWidget);
    });

    testWidgets('account and settings stay available when declined',
        (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('Ne'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paskyra').last);
      await tester.pumpAndSettle();

      expect(find.text('Nustatymai'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('bottom bar has the three Lithuanian destinations',
        (tester) async {
      await _pumpApp(tester, stored: {'age_confirmed': true});

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in ['Parduotuvės', 'Paieška', 'Paskyra']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('tab screens have a back action to the first tab',
        (tester) async {
      await _pumpApp(tester, stored: {'age_confirmed': true});

      await tester.tap(find.text('Paieška').last);
      await tester.pumpAndSettle();
      expect(find.text('Produktų paieška bus čia.'), findsOneWidget);

      await tester.tap(find.byTooltip('Atgal'));
      await tester.pumpAndSettle();
      expect(find.text('Parduotuvių sąrašas bus čia.'), findsOneWidget);
    });

    testWidgets('settings opens from Paskyra and has a back arrow',
        (tester) async {
      await _pumpApp(tester, stored: {'age_confirmed': true});

      await tester.tap(find.text('Paskyra').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nustatymai'));
      await tester.pumpAndSettle();

      expect(find.text('Paieškos spindulys: 10 km'), findsOneWidget);

      await tester.tap(find.byTooltip('Atgal'));
      await tester.pumpAndSettle();
      expect(find.text('Nustatymai'), findsOneWidget);
      expect(find.text('Paieškos spindulys: 10 km'), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('are restored from the device', (tester) async {
      await _pumpApp(
        tester,
        stored: {
          'age_confirmed': true,
          'theme_mode': 'dark',
          'city': 'Kaunas',
          'search_radius_km': 25,
        },
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Paskyra').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nustatymai'));
      await tester.pumpAndSettle();

      expect(find.text('Paieškos spindulys: 25 km'), findsOneWidget);
      expect(find.text('Kaunas'), findsOneWidget);
    });

    testWidgets('theme choice is applied and persisted', (tester) async {
      final prefs = await _pumpApp(tester, stored: {'age_confirmed': true});

      await tester.tap(find.text('Paskyra').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nustatymai'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamsi'));
      await tester.pumpAndSettle();

      expect(prefs.themeMode, ThemeMode.dark);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });

    test('out-of-range stored radius is clamped', () async {
      SharedPreferences.setMockInitialValues({'search_radius_km': 500});
      final prefs = AppPreferences(await SharedPreferences.getInstance());
      expect(prefs.radiusKm, maxRadiusKm);
    });
  });
}
