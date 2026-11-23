import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/api_error_messages_lt.dart';
import '../storage/session_storage.dart';
import 'auth_models.dart';

/// Account session: sign-in state, token storage and the account API calls.
///
/// Every method that talks to the server throws [ApiException] with a
/// Lithuanian message; the screens show it next to the field or as a general
/// error. Permissions are never decided here, only on the server.
class AuthController extends Notifier<AuthState> {
  ApiClient get _api => ref.read(apiClientProvider);
  SessionStorage get _storage => ref.read(sessionStorageProvider);

  @override
  AuthState build() {
    Future<void>.microtask(restore);
    return const AuthState.loading();
  }

  /// Checks the stored token (if any) with the server at app start.
  Future<void> restore() async {
    String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      // Unreadable secure storage counts as "not signed in".
    }
    if (!ref.mounted) {
      return;
    }
    if (token == null || token.isEmpty) {
      state = const AuthState.signedOut();
      return;
    }

    try {
      final data = await _api.get('/auth/me');
      if (ref.mounted) {
        state = AuthState.signedIn(AuthUser.fromJson(_asMap(data)));
      }
    } on ApiException {
      // A 401 was already handled by [onSessionRejected] (token cleared). For
      // other failures (offline) the token is kept; the user just sees the
      // signed-out screen until the next successful sign-in.
      if (ref.mounted && state.status == AuthStatus.loading) {
        state = const AuthState.signedOut();
      }
    }
  }

  Future<void> register(String email, String password) async {
    final data = await _api.post(
      '/auth/register',
      body: {'email': email, 'password': password},
    );
    await _completeSignIn(data);
  }

  Future<void> login(String email, String password) async {
    final data = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    await _completeSignIn(data);
  }

  /// Signs out at once; ending the server session is best effort (the token
  /// expires on its own after 30 minutes anyway).
  Future<void> logout() async {
    state = const AuthState.signedOut();
    try {
      await _api.post('/auth/logout');
    } on ApiException {
      // Offline or token already invalid: nothing more to do.
    }
    await _storage.clear();
  }

  Future<void> forgotPassword(String email) =>
      _api.post('/auth/forgot-password', body: {'email': email});

  Future<void> resetPassword(String token, String newPassword) => _api.post(
        '/auth/reset-password',
        body: {'token': token, 'newPassword': newPassword},
      );

  /// Deletes the account after the server re-checked [password].
  Future<void> deleteAccount(String password) async {
    await _api.delete('/auth/account', body: {'password': password});
    await _storage.clear();
    if (ref.mounted) {
      state = const AuthState.signedOut();
    }
  }

  /// The server answered 401 to a request that carried our token.
  Future<void> onSessionRejected() async {
    await _storage.clear();
    if (!ref.mounted) {
      return;
    }
    // Only a user who was signed in is told that the session ended.
    state = AuthState.signedOut(sessionExpired: state.isSignedIn);
  }

  Future<void> _completeSignIn(dynamic data) async {
    final map = _asMap(data);
    final token = map['token'];
    final user = map['user'];
    if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
      throw _malformedResponse();
    }
    final parsed = AuthUser.fromJson(user);
    await _storage.writeToken(token);
    state = AuthState.signedIn(parsed);
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw _malformedResponse();
  }

  ApiException _malformedResponse() => const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
