import 'package:alusekis/core/api/api_error.dart';
import 'package:alusekis/core/api/api_error_messages_lt.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _exception(
  DioExceptionType type, {
  int? status,
  Object? body,
}) {
  final options = RequestOptions(path: '/api/v1/x');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: body,
          ),
  );
}

void main() {
  group('mapDioException', () {
    test('maps the standard error DTO to a Lithuanian message', () {
      final error = mapDioException(
        _exception(
          DioExceptionType.badResponse,
          status: 404,
          body: {
            'code': 'not_found',
            'message': 'The requested resource was not found.',
            'requestId': 'abc:1',
          },
        ),
      );

      expect(error.kind, ApiErrorKind.server);
      expect(error.code, 'not_found');
      expect(error.requestId, 'abc:1');
      expect(error.userMessage, 'Nieko nerasta.');
    });

    test('never exposes server message or request id to the user', () {
      final error = mapDioException(
        _exception(
          DioExceptionType.badResponse,
          status: 500,
          body: {
            'code': 'internal_error',
            'message': 'NullReferenceException at Foo.Bar',
            'requestId': 'abc:2',
          },
        ),
      );

      expect(error.userMessage, isNot(contains('NullReference')));
      expect(error.userMessage, isNot(contains('abc:2')));
      expect(error.userMessage, isNot(contains('500')));
    });

    test('falls back to the status code for unknown codes', () {
      final error = mapDioException(
        _exception(
          DioExceptionType.badResponse,
          status: 409,
          body: {'code': 'something_new', 'message': 'x', 'requestId': 'r'},
        ),
      );

      expect(error.userMessage, messageForServerError(statusCode: 409));
    });

    test('handles non-JSON error bodies', () {
      final error = mapDioException(
        _exception(
          DioExceptionType.badResponse,
          status: 503,
          body: '<html>Bad gateway</html>',
        ),
      );

      expect(error.kind, ApiErrorKind.server);
      expect(error.code, isNull);
      expect(error.userMessage, contains('laikinai nepasiekiama'));
    });

    test('distinguishes timeouts and connection problems', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final error = mapDioException(_exception(type));
        expect(error.kind, ApiErrorKind.timeout);
        expect(error.userMessage, messageForTimeout);
      }

      final network = mapDioException(
        _exception(DioExceptionType.connectionError),
      );
      expect(network.kind, ApiErrorKind.network);
      expect(network.userMessage, messageForNetwork);
    });

    test('server request_timeout code has the timeout message', () {
      final error = mapDioException(
        _exception(
          DioExceptionType.badResponse,
          status: 504,
          body: {'code': 'request_timeout', 'message': 'm', 'requestId': 'r'},
        ),
      );
      expect(error.userMessage, messageForTimeout);
    });
  });
}
