import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/storage/session_storage.dart';
import 'package:dio/dio.dart';

/// Token storage that lives in memory (the real one needs a platform plugin).
class InMemorySessionStorage extends SessionStorage {
  InMemorySessionStorage([this.token]);

  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

/// Replaces the network: answers requests from scripted replies and records them.
///
/// Replies for the same route are used in order; the last one repeats.
class FakeApiAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, List<_Reply>> _routes = {};

  /// Scripts an answer for [method] [path], e.g. `reply('POST', '/api/v1/auth/login', body: {...})`.
  void reply(String method, String path, {int status = 200, Object? body}) {
    _routes.putIfAbsent('$method $path', () => []).add(_Reply(status, body));
  }

  /// Scripts a standard error DTO.
  void replyError(String method, String path, int status, String code) =>
      reply(
        method,
        path,
        status: status,
        body: {'code': code, 'message': 'server text', 'requestId': 'req-1'},
      );

  List<RequestOptions> requestsTo(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.path}';
    final replies = _routes[key];
    if (replies == null) {
      throw StateError('No fake reply scripted for $key');
    }
    final reply = replies.length > 1 ? replies.removeAt(0) : replies.first;
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A successful register/login response body.
Map<String, Object> authResponse({
  String email = 'jonas@example.lt',
  String token = 'token-1',
}) =>
    {
      'user': {'id': 2, 'email': email, 'displayName': 'jonas', 'role': 'User'},
      'token': token,
      'expiresAt': '2026-11-23T12:30:00Z',
    };

Map<String, Object> meResponse({String email = 'jonas@example.lt'}) =>
    {'id': 2, 'email': email, 'displayName': 'jonas', 'role': 'User'};
