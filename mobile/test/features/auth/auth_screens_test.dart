import 'package:alusekis/app.dart';
import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/storage/app_preferences.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

const _register = '/api/v1/auth/register';
const _login = '/api/v1/auth/login';
const _logout = '/api/v1/auth/logout';
const _me = '/api/v1/auth/me';
const _account = '/api/v1/auth/account';
const _forgot = '/api/v1/auth/forgot-password';
const _reset = '/api/v1/auth/reset-password';

const _goodPassword = 'correct horse battery';

late FakeApiAdapter _adapter;
late InMemorySessionStorage _storage;

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  String? storedToken,
}) async {
  SharedPreferences.setMockInitialValues({'age_confirmed': true});
  final prefs = AppPreferences(await SharedPreferences.getInstance());
  _storage = InMemorySessionStorage(storedToken);
  scriptStoreReplies(_adapter); // the start screen is the stores screen
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        sessionStorageProvider.overrideWithValue(_storage),
        httpClientAdapterProvider.overrideWithValue(_adapter),
        mapProviderProvider.overrideWithValue(const FakeMapProvider()),
      ],
      child: const AlusekisApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(AlusekisApp)));
}

Future<void> _openAccount(WidgetTester tester) async {
  await tester.tap(find.text('Paskyra').last);
  await tester.pumpAndSettle();
}

Future<void> _tapListTile(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(ListTile, title));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, int fieldIndex, String text) async {
  await tester.enterText(find.byType(TextFormField).at(fieldIndex), text);
}

Future<void> _submit(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _adapter = FakeApiAdapter();
  });

  group('account screen', () {
    testWidgets('signed out offers sign-in, registration and recovery',
        (tester) async {
      await _pumpApp(tester);
      await _openAccount(tester);

      for (final label in [
        'Prisijungti',
        'Registruotis',
        'Atkurti slaptažodį',
        'Nustatymai',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Atsijungti'), findsNothing);
      expect(find.text('Ištrinti paskyrą'), findsNothing);
    });

    testWidgets('signed in shows the e-mail, sign-out and deletion',
        (tester) async {
      _adapter.reply('GET', _me, body: meResponse());
      await _pumpApp(tester, storedToken: 'stored');
      await _openAccount(tester);

      expect(find.text('jonas@example.lt'), findsOneWidget);
      expect(find.text('Atsijungti'), findsOneWidget);
      expect(find.text('Ištrinti paskyrą'), findsOneWidget);
      expect(find.text('Prisijungti'), findsNothing);
    });

    testWidgets('sign-out returns to the signed-out menu', (tester) async {
      _adapter.reply('GET', _me, body: meResponse());
      _adapter.reply('POST', _logout, status: 204);
      await _pumpApp(tester, storedToken: 'stored');
      await _openAccount(tester);

      await _tapListTile(tester, 'Atsijungti');

      expect(find.text('Prisijungti'), findsOneWidget);
      expect(find.text('Atsijungti'), findsNothing);
      expect(_storage.token, isNull);
    });
  });

  group('registration', () {
    testWidgets('empty or short input is caught before any request',
        (tester) async {
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Registruotis');

      await _submit(tester, 'Registruotis');
      expect(find.text('Įveskite el. pašto adresą.'), findsOneWidget);
      expect(find.text('Įveskite slaptažodį.'), findsOneWidget);

      await _type(tester, 0, 'jonas@example.lt');
      await _type(tester, 1, 'short');
      await _submit(tester, 'Registruotis');
      expect(find.text('Slaptažodis turi būti 12–128 simbolių.'), findsOneWidget);
      expect(_adapter.requestsTo('POST', _register), isEmpty);
    });

    testWidgets('a taken e-mail is explained next to the e-mail field',
        (tester) async {
      _adapter.replyError('POST', _register, 409, 'email_taken');
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Registruotis');

      await _type(tester, 0, 'jonas@example.lt');
      await _type(tester, 1, _goodPassword);
      await _submit(tester, 'Registruotis');

      expect(find.text('Šis el. paštas jau užregistruotas.'), findsOneWidget);
      // It sits in the field, not in a general banner (the banner has an icon).
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('server text'), findsNothing);
      expect(_storage.token, isNull);
    });

    testWidgets('success signs in and returns to the account screen',
        (tester) async {
      _adapter.reply('POST', _register, status: 201, body: authResponse(token: 'new'));
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Registruotis');

      await _type(tester, 0, 'jonas@example.lt');
      await _type(tester, 1, _goodPassword);
      await _submit(tester, 'Registruotis');

      expect(find.text('jonas@example.lt'), findsOneWidget);
      expect(find.text('Atsijungti'), findsOneWidget);
      expect(_storage.token, 'new');
    });
  });

  group('login', () {
    testWidgets('wrong credentials show one general message, not a field',
        (tester) async {
      _adapter.replyError('POST', _login, 401, 'invalid_credentials');
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Prisijungti');

      await _type(tester, 0, 'jonas@example.lt');
      await _type(tester, 1, 'wrong password!!');
      await _submit(tester, 'Prisijungti');

      expect(find.text('Neteisingas el. paštas arba slaptažodis.'), findsOneWidget);
      expect(find.text('Sesija baigėsi. Prisijunkite iš naujo.'), findsNothing);
    });

    testWidgets('a rate-limit answer is shown without technical details',
        (tester) async {
      _adapter.replyError('POST', _login, 429, 'too_many_requests');
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Prisijungti');

      await _type(tester, 0, 'jonas@example.lt');
      await _type(tester, 1, _goodPassword);
      await _submit(tester, 'Prisijungti');

      expect(find.textContaining('Per daug bandymų'), findsOneWidget);
      expect(find.textContaining('429'), findsNothing);
      expect(find.textContaining('too_many'), findsNothing);
    });

    testWidgets('a rejected token sends the user to the login screen',
        (tester) async {
      _adapter.reply('GET', _me, body: meResponse()); // start-up check
      final container = await _pumpApp(tester, storedToken: 'stored');
      _adapter.replyError('GET', '/api/v1/ping', 401, 'unauthorized');

      container.read(apiClientProvider).get('/ping').ignore();
      await tester.pumpAndSettle();

      expect(find.text('Sesija baigėsi. Prisijunkite iš naujo.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Prisijungti'), findsOneWidget);
      expect(_storage.token, isNull);
    });
  });

  group('password recovery', () {
    testWidgets('request then reset with a used code shows the error at the code field',
        (tester) async {
      _adapter.reply('POST', _forgot, status: 202);
      _adapter.replyError('POST', _reset, 400, 'invalid_reset_token');
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Atkurti slaptažodį');

      await _type(tester, 0, 'jonas@example.lt');
      await _submit(tester, 'Siųsti nuorodą');
      expect(find.textContaining('nuoroda išsiųsta'), findsOneWidget);

      await tester.tap(find.text('Turiu atkūrimo kodą'));
      await tester.pumpAndSettle();
      await _type(tester, 0, 'alusekis://reset-password?token=used-token');
      await _type(tester, 1, 'a brand new password');
      await _submit(tester, 'Pakeisti slaptažodį');

      expect(
        find.text('Atkūrimo kodas neteisingas, nebegalioja arba jau panaudotas.'),
        findsOneWidget,
      );
      // The token is extracted from the pasted link.
      expect(_adapter.requestsTo('POST', _reset).single.data, {
        'token': 'used-token',
        'newPassword': 'a brand new password',
      });
    });

    testWidgets('a valid reset goes to sign-in with a confirmation',
        (tester) async {
      _adapter.reply('POST', _forgot, status: 202);
      _adapter.reply('POST', _reset, status: 204);
      await _pumpApp(tester);
      await _openAccount(tester);
      await _tapListTile(tester, 'Atkurti slaptažodį');
      await _type(tester, 0, 'jonas@example.lt');
      await _submit(tester, 'Siųsti nuorodą');
      await tester.tap(find.text('Turiu atkūrimo kodą'));
      await tester.pumpAndSettle();

      await _type(tester, 0, 'good-token');
      await _type(tester, 1, 'a brand new password');
      await _submit(tester, 'Pakeisti slaptažodį');

      expect(find.textContaining('Slaptažodis pakeistas'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Prisijungti'), findsOneWidget);
    });
  });

  group('account deletion', () {
    Future<void> openDialog(WidgetTester tester) async {
      _adapter.reply('GET', _me, body: meResponse());
      await _pumpApp(tester, storedToken: 'stored');
      await _openAccount(tester);
      await _tapListTile(tester, 'Ištrinti paskyrą');
    }

    testWidgets('the dialog names the consequences and asks for the password',
        (tester) async {
      await openDialog(tester);

      expect(find.text('Ištrinti paskyrą?'), findsOneWidget);
      expect(find.textContaining('negrįžtamai'), findsOneWidget);
      expect(find.textContaining('liks viešai'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Atšaukti'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Atšaukti'));
      await tester.pumpAndSettle();

      expect(find.text('Ištrinti paskyrą?'), findsNothing);
      expect(find.text('Atsijungti'), findsOneWidget);
      expect(_adapter.requestsTo('DELETE', _account), isEmpty);
    });

    testWidgets('an empty password is not sent', (tester) async {
      await openDialog(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Ištrinti paskyrą'));
      await tester.pumpAndSettle();

      expect(find.text('Įveskite slaptažodį.'), findsOneWidget);
      expect(_adapter.requestsTo('DELETE', _account), isEmpty);
    });

    testWidgets('a wrong password is explained in the dialog and keeps the account',
        (tester) async {
      _adapter.replyError('DELETE', _account, 403, 'invalid_password');
      await openDialog(tester);

      await tester.enterText(find.byType(TextFormField), 'not my password');
      await tester.tap(find.widgetWithText(FilledButton, 'Ištrinti paskyrą'));
      await tester.pumpAndSettle();

      expect(find.text('Neteisingas slaptažodis.'), findsOneWidget);
      expect(find.text('Ištrinti paskyrą?'), findsOneWidget); // still open
      expect(_storage.token, 'stored'); // still signed in
    });

    testWidgets('the right password deletes the account and signs out',
        (tester) async {
      _adapter.reply('DELETE', _account, status: 204);
      await openDialog(tester);

      await tester.enterText(find.byType(TextFormField), _goodPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Ištrinti paskyrą'));
      await tester.pumpAndSettle();

      expect(find.text('Ištrinti paskyrą?'), findsNothing);
      expect(find.text('Paskyra ištrinta.'), findsOneWidget);
      expect(find.text('Prisijungti'), findsOneWidget);
      expect(_adapter.requestsTo('DELETE', _account).single.data, {
        'password': _goodPassword,
      });
      expect(_storage.token, isNull);
    });
  });
}
