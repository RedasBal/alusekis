import 'dart:io' show SocketException;

import 'package:dio/dio.dart';

import 'api_error_messages_lt.dart';

enum ApiErrorKind {
  /// The server answered with an error (see [ApiError.code]).
  server,

  /// No connection or the server could not be reached.
  network,

  /// The server did not answer within the time limit.
  timeout,

  /// The request was cancelled by the app.
  cancelled,

  /// Anything else, including unreadable responses.
  unknown,
}

/// A failed API call, already translated for the user.
class ApiError {
  const ApiError({
    required this.kind,
    required this.userMessage,
    this.code,
    this.requestId,
    this.statusCode,
    this.body,
  });

  final ApiErrorKind kind;

  /// Lithuanian text that is safe to show to the user (no technical details).
  final String userMessage;

  /// Server error code from the `{code, message, requestId}` DTO, if any.
  final String? code;

  /// For logs and support only; never shown in the UI.
  final String? requestId;

  final int? statusCode;

  /// The whole error body when it was JSON, for codes that carry extra data
  /// (e.g. `previousPriceCents` of `large_price_change`). Never shown as is.
  final Map<String, dynamic>? body;

  @override
  String toString() =>
      'ApiError(kind: $kind, code: $code, status: $statusCode, requestId: $requestId)';
}

/// Thrown by `ApiClient`; carries a user-ready [error].
class ApiException implements Exception {
  const ApiException(this.error);

  final ApiError error;

  String get userMessage => error.userMessage;

  @override
  String toString() => 'ApiException($error)';
}

/// Converts a Dio failure into an [ApiError] with a Lithuanian message.
ApiError mapDioException(DioException exception) {
  switch (exception.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return ApiError(
        kind: ApiErrorKind.timeout,
        userMessage: messageForTimeout,
      );
    case DioExceptionType.connectionError:
      return ApiError(
        kind: ApiErrorKind.network,
        userMessage: messageForNetwork,
      );
    case DioExceptionType.cancel:
      return ApiError(
        kind: ApiErrorKind.cancelled,
        userMessage: messageForUnknown,
      );
    case DioExceptionType.badResponse:
      return _fromResponse(exception.response);
    case DioExceptionType.badCertificate:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.unknown:
      return exception.error is SocketException
          ? const ApiError(
              kind: ApiErrorKind.network,
              userMessage: messageForNetwork,
            )
          : const ApiError(
              kind: ApiErrorKind.unknown,
              userMessage: messageForUnknown,
            );
  }
}

ApiError _fromResponse(Response<dynamic>? response) {
  final status = response?.statusCode;
  final data = response?.data;

  String? code;
  String? requestId;
  Map<String, dynamic>? body;
  if (data is Map<String, dynamic>) {
    body = data;
    final rawCode = data['code'];
    final rawRequestId = data['requestId'];
    code = rawCode is String ? rawCode : null;
    requestId = rawRequestId is String ? rawRequestId : null;
  }

  return ApiError(
    kind: ApiErrorKind.server,
    code: code,
    requestId: requestId,
    statusCode: status,
    body: body,
    userMessage: messageForServerError(code: code, statusCode: status),
  );
}
