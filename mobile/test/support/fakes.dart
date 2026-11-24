import 'dart:convert';
import 'dart:typed_data';

import 'package:alusekis/core/storage/session_storage.dart';
import 'package:alusekis/features/stores/location_service.dart';
import 'package:alusekis/features/stores/map_provider.dart';
import 'package:alusekis/features/stores/store_models.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

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
  const _Reply(this.status, this.body, {this.offline = false});

  final int status;
  final Object? body;

  /// The request fails like a phone without a connection.
  final bool offline;
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

  /// Discards earlier scripted answers for the route and uses this one from now on.
  void replace(String method, String path, {int status = 200, Object? body}) {
    _routes['$method $path'] = [_Reply(status, body)];
  }

  /// Makes the route fail as if there were no connection (replaces earlier answers).
  void replaceWithOffline(String method, String path) {
    _routes['$method $path'] = [const _Reply(0, null, offline: true)];
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
    if (reply.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
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

// ---- stores ----

Map<String, Object> storeJson(
  int id,
  String name,
  String address, {
  double? distanceKm,
  String city = 'Vilnius',
}) =>
    {
      'id': id,
      'name': name,
      'address': address,
      'latitude': 54.7,
      'longitude': 25.2,
      'distanceKm': ?distanceKm,
      'city': {'id': 1, 'name': city},
    };

/// The server answers the stores screen's start-up requests (city list and the
/// stores of Vilnius), so screens that show it need no further scripting.
void scriptStoreReplies(FakeApiAdapter adapter) {
  adapter.reply(
    'GET',
    '/api/v1/cities',
    body: {
      'items': [
        {'id': 2, 'name': 'Kaunas'},
        {'id': 3, 'name': 'Klaipėda'},
        {'id': 1, 'name': 'Vilnius'},
      ],
    },
  );
  adapter.reply(
    'GET',
    '/api/v1/stores',
    body: {
      'items': [
        storeJson(1, 'Iki', 'Žirmūnų g. 64'),
        storeJson(2, 'Maxima XX', 'Ukmergės g. 282'),
      ],
    },
  );
}

/// Lists the stores as buttons instead of drawing real map tiles (no network in tests).
class FakeMapProvider implements MapProvider {
  const FakeMapProvider();

  @override
  Widget build(
    BuildContext context, {
    required List<StoreItem> stores,
    required void Function(StoreItem store) onStoreTap,
    GeoPoint? origin,
  }) =>
      Column(
        children: [
          const Text('FAKE-MAP'),
          for (final s in stores)
            TextButton(
              onPressed: () => onStoreTap(s),
              child: Text('pin ${s.name}'),
            ),
        ],
      );
}

class FakeLocationService implements LocationService {
  FakeLocationService(this.result);

  final LocationResult result;
  int calls = 0;

  @override
  Future<LocationResult> requestCurrentPosition() async {
    calls++;
    return result;
  }

  @override
  Future<void> openAppSettings() async {}
}
