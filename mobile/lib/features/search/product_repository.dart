import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'product_models.dart';

/// Product search on the server. Guests may call it.
class ProductRepository {
  ProductRepository(this._api);

  final ApiClient _api;

  /// [query] must already be trimmed and 2-100 characters long (see
  /// `isSearchable`). Pass a [cancelToken] to abandon the request when the
  /// user keeps typing.
  Future<List<ProductSearchItem>> search(String query, {CancelToken? cancelToken}) async {
    final data = await _api.get(
      '/products/search',
      queryParameters: {'q': query},
      cancelToken: cancelToken,
    );
    try {
      final items = (data as Map<String, dynamic>)['items'] as List<dynamic>;
      return [
        for (final item in items) ProductSearchItem.fromJson(item as Map<String, dynamic>),
      ];
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }
}

final productRepositoryProvider =
    Provider<ProductRepository>((ref) => ProductRepository(ref.watch(apiClientProvider)));
