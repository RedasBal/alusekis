import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../storage/session_storage.dart';
import 'api_config.dart';
import 'api_error.dart';

/// Supplies the stored access token (or null when signed out).
typedef TokenReader = Future<String?> Function();

const String _authorizationHeader = 'Authorization';

/// Called when the server rejects a token the app had sent (HTTP 401).
typedef UnauthorizedHandler = Future<void> Function();

/// Thin JSON client for the Alusekis server (`/api/v1`).
///
/// Every failure is thrown as an [ApiException] whose message is ready to show
/// to the user. Feature code never sees [DioException].
///
/// When a [readToken] is given, the access token is added to each request as
/// `Authorization: Bearer ...`. A 401 answer to such a request calls
/// [onUnauthorized] (sign out); a 401 to a request without a token (e.g. a
/// failed login) does not.
class ApiClient {
  ApiClient(
    this._dio, {
    TokenReader? readToken,
    UnauthorizedHandler? onUnauthorized,
  }) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await readToken?.call();
          if (token != null && token.isNotEmpty) {
            options.headers[_authorizationHeader] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final hadToken =
              error.requestOptions.headers.containsKey(_authorizationHeader);
          if (error.response?.statusCode == 401 && hadToken) {
            await onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Creates a client for [baseUrl] with the standard JSON setup and 10 s timeouts.
  factory ApiClient.create({
    String baseUrl = apiBaseUrl,
    TokenReader? readToken,
    UnauthorizedHandler? onUnauthorized,
    HttpClientAdapter? adapter,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: apiTimeout,
        sendTimeout: apiTimeout,
        receiveTimeout: apiTimeout,
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        headers: {Headers.acceptHeader: Headers.jsonContentType},
      ),
    );
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
    }
    return ApiClient(
      dio,
      readToken: readToken,
      onUnauthorized: onUnauthorized,
    );
  }

  final Dio _dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.get<dynamic>(
          '$apiPrefix$path',
          queryParameters: queryParameters,
          cancelToken: cancelToken,
        ),
      );

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.post<dynamic>(
          '$apiPrefix$path',
          data: body,
          options: Options(headers: headers),
          cancelToken: cancelToken,
        ),
      );

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.delete<dynamic>(
          '$apiPrefix$path',
          data: body,
          options: Options(headers: headers),
          cancelToken: cancelToken,
        ),
      );

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      final error = mapDioException(e);
      // Technical details go to the debug log only, never to the UI.
      debugPrint('API error: $error');
      throw ApiException(error);
    }
  }
}

/// Lets tests (and only tests) replace the network layer.
final httpClientAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient.create(
    adapter: ref.watch(httpClientAdapterProvider),
    readToken: () => ref.read(sessionStorageProvider).readToken(),
    onUnauthorized: () =>
        ref.read(authControllerProvider.notifier).onSessionRejected(),
  ),
);
