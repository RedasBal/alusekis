import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';
import 'api_error.dart';

/// Thin JSON client for the Alusekis server (`/api/v1`).
///
/// Every failure is thrown as an [ApiException] whose message is ready to show
/// to the user. Feature code never sees [DioException].
class ApiClient {
  ApiClient(this._dio);

  /// Creates a client for [baseUrl] with the standard JSON setup and 10 s timeouts.
  factory ApiClient.create({String baseUrl = apiBaseUrl}) {
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
    return ApiClient(dio);
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

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create());
