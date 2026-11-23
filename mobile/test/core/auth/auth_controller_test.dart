import 'package:alusekis/core/api/api_client.dart';
import 'package:alusekis/core/api/api_error.dart';
import 'package:alusekis/core/auth/auth_controller.dart';
import 'package:alusekis/core/auth/auth_models.dart';
import 'package:alusekis/core/storage/session_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

const _login = '/api/v1/auth/login';
const _register = '/api/v1/auth/register';
const _logout = '/api/v1/auth/logout';
const _me = '/api/v1/auth/me';
const _account = '/api/v1/auth/account';

ProviderContainer _container(
  FakeApiAdapter adapter,
  InMemorySessionStorage storage,
) {
  final container = ProviderContainer(
    overrides: [
      httpClientAdapterProvider.overrideWithValue(adapter),
      sessionStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  // In the app the router listens to the auth state from the start, which
  // builds the controller and begins the start-up token check.
  container.listen(authControllerProvider, (_, _) {});
  return container;
}

/// Lets the start-up token check (storage read + one request) finish.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<ApiException> _expectApiError(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  throw TestFailure('Expected an ApiException');
}

void main() {
  late FakeApiAdapter adapter;
  late InMemorySessionStorage storage;

  setUp(() {
    adapter = FakeApiAdapter();
    storage = InMemorySessionStorage();
  });

  group('start-up', () {
    test('without a stored token the user is signed out', () async {
      final container = _container(adapter, storage);
      expect(container.read(authControllerProvider).status, AuthStatus.loading);

      await _settle();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(adapter.requests, isEmpty);
    });

    test('a valid stored token signs the user in', () async {
      storage.token = 'stored';
      adapter.reply('GET', _me, body: meResponse());
      final container = _container(adapter, storage);

      await _settle();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedIn);
      expect(state.user!.email, 'jonas@example.lt');
      expect(
        adapter.requestsTo('GET', _me).single.headers['Authorization'],
        'Bearer stored',
      );
    });

    test('a rejected stored token is dropped without an "expired" notice',
        () async {
      storage.token = 'stale';
      adapter.replyError('GET', _me, 401, 'unauthorized');
      final container = _container(adapter, storage);

      await _settle();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.sessionExpired, isFalse);
      expect(storage.token, isNull);
    });

    test('an unreachable server keeps the token', () async {
      storage.token = 'kept';
      adapter.replyError('GET', _me, 503, 'service_unavailable');
      final container = _container(adapter, storage);

      await _settle();

      expect(container.read(authControllerProvider).status, AuthStatus.signedOut);
      expect(storage.token, 'kept');
    });
  });

  group('login and registration', () {
    test('login stores the token and signs in', () async {
      adapter.reply('POST', _login, body: authResponse(token: 'abc'));
      final container = _container(adapter, storage);
      await _settle();

      await container
          .read(authControllerProvider.notifier)
          .login('jonas@example.lt', 'correct horse battery');

      expect(storage.token, 'abc');
      expect(container.read(authControllerProvider).isSignedIn, isTrue);
      expect(adapter.requestsTo('POST', _login).single.data, {
        'email': 'jonas@example.lt',
        'password': 'correct horse battery',
      });
      // No token existed yet, so none was sent.
      expect(
        adapter.requestsTo('POST', _login).single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('wrong credentials give a generic message and change nothing',
        () async {
      adapter.replyError('POST', _login, 401, 'invalid_credentials');
      final container = _container(adapter, storage);
      await _settle();

      final error = await _expectApiError(
        container.read(authControllerProvider.notifier).login('a@b.lt', 'x'),
      );

      expect(error.error.code, 'invalid_credentials');
      expect(error.userMessage, 'Neteisingas el. paštas arba slaptažodis.');
      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.sessionExpired, isFalse); // a failed login is not an expired session
      expect(storage.token, isNull);
    });

    test('registration signs in and stores the token', () async {
      adapter.reply('POST', _register, status: 201, body: authResponse(token: 'new'));
      final container = _container(adapter, storage);
      await _settle();

      await container
          .read(authControllerProvider.notifier)
          .register('jonas@example.lt', 'correct horse battery');

      expect(storage.token, 'new');
      expect(container.read(authControllerProvider).user!.email, 'jonas@example.lt');
    });

    test('duplicate e-mail is reported in Lithuanian', () async {
      adapter.replyError('POST', _register, 409, 'email_taken');
      final container = _container(adapter, storage);
      await _settle();

      final error = await _expectApiError(
        container
            .read(authControllerProvider.notifier)
            .register('jonas@example.lt', 'correct horse battery'),
      );

      expect(error.userMessage, 'Šis el. paštas jau užregistruotas.');
      expect(storage.token, isNull);
    });
  });

  group('signed-in behaviour', () {
    Future<ProviderContainer> signedIn() async {
      adapter.reply('POST', _login, body: authResponse(token: 'abc'));
      final container = _container(adapter, storage);
      await _settle();
      await container
          .read(authControllerProvider.notifier)
          .login('jonas@example.lt', 'correct horse battery');
      return container;
    }

    test('the token is added to later requests', () async {
      final container = await signedIn();
      adapter.reply('GET', '/api/v1/ping', body: {'status': 'ok'});

      await container.read(apiClientProvider).get('/ping');

      expect(
        adapter.requestsTo('GET', '/api/v1/ping').single.headers['Authorization'],
        'Bearer abc',
      );
    });

    test('a 401 signs the user out and flags the expired session', () async {
      final container = await signedIn();
      adapter.replyError('GET', '/api/v1/ping', 401, 'unauthorized');

      await _expectApiError(container.read(apiClientProvider).get('/ping'));

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.sessionExpired, isTrue);
      expect(storage.token, isNull);
    });

    test('logout signs out at once, ends the session and clears the token',
        () async {
      final container = await signedIn();
      adapter.reply('POST', _logout, status: 204);

      await container.read(authControllerProvider.notifier).logout();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.sessionExpired, isFalse);
      expect(storage.token, isNull);
      expect(
        adapter.requestsTo('POST', _logout).single.headers['Authorization'],
        'Bearer abc',
      );
    });

    test('logout still works when the server cannot be reached', () async {
      final container = await signedIn();
      adapter.replyError('POST', _logout, 503, 'service_unavailable');

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).status, AuthStatus.signedOut);
      expect(storage.token, isNull);
    });

    test('logout with an already expired token is not shown as "expired"',
        () async {
      final container = await signedIn();
      adapter.replyError('POST', _logout, 401, 'unauthorized');

      await container.read(authControllerProvider.notifier).logout();

      expect(container.read(authControllerProvider).sessionExpired, isFalse);
    });

    test('deleting the account sends the password and signs out', () async {
      final container = await signedIn();
      adapter.reply('DELETE', _account, status: 204);

      await container
          .read(authControllerProvider.notifier)
          .deleteAccount('correct horse battery');

      expect(adapter.requestsTo('DELETE', _account).single.data, {
        'password': 'correct horse battery',
      });
      expect(container.read(authControllerProvider).status, AuthStatus.signedOut);
      expect(storage.token, isNull);
    });

    test('deleting with a wrong password keeps the user signed in', () async {
      final container = await signedIn();
      adapter.replyError('DELETE', _account, 403, 'invalid_password');

      final error = await _expectApiError(
        container.read(authControllerProvider.notifier).deleteAccount('nope'),
      );

      expect(error.userMessage, 'Neteisingas slaptažodis.');
      final state = container.read(authControllerProvider);
      expect(state.isSignedIn, isTrue);
      expect(state.sessionExpired, isFalse);
      expect(storage.token, 'abc');
    });
  });

  group('password recovery', () {
    test('forgot and reset send the expected bodies', () async {
      adapter.reply('POST', '/api/v1/auth/forgot-password', status: 202);
      adapter.reply('POST', '/api/v1/auth/reset-password', status: 204);
      final container = _container(adapter, storage);
      await _settle();
      final auth = container.read(authControllerProvider.notifier);

      await auth.forgotPassword('jonas@example.lt');
      await auth.resetPassword('tok', 'a brand new password');

      expect(
        adapter.requestsTo('POST', '/api/v1/auth/forgot-password').single.data,
        {'email': 'jonas@example.lt'},
      );
      expect(
        adapter.requestsTo('POST', '/api/v1/auth/reset-password').single.data,
        {'token': 'tok', 'newPassword': 'a brand new password'},
      );
    });

    test('a used or expired code is explained in Lithuanian', () async {
      adapter.replyError('POST', '/api/v1/auth/reset-password', 400, 'invalid_reset_token');
      final container = _container(adapter, storage);
      await _settle();

      final error = await _expectApiError(
        container.read(authControllerProvider.notifier).resetPassword('t', 'a brand new password'),
      );

      expect(error.userMessage, contains('Atkūrimo kodas'));
    });
  });
}
