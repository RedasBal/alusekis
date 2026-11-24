import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../compare/compare_models.dart';
import '../history/history_models.dart';
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

  /// The product's newest valid price in every store, sorted by the server.
  Future<ProductComparison> productPrices(
    int productId,
    PriceSort sort, {
    CancelToken? cancelToken,
  }) async {
    final data = await _api.get(
      '/products/$productId/prices',
      queryParameters: {'sort': sort.apiValue},
      cancelToken: cancelToken,
    );
    try {
      return ProductComparison.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw _unreadable();
    } on FormatException {
      throw _unreadable();
    }
  }

  /// The recorded prices of one product in one store over the last [period]
  /// (the server fixes the window by its own clock).
  Future<PriceHistory> productStoreHistory(
    int productId,
    int storeId,
    HistoryPeriod period, {
    CancelToken? cancelToken,
  }) async {
    final data = await _api.get(
      '/products/$productId/stores/$storeId/history',
      queryParameters: {'days': period.days},
      cancelToken: cancelToken,
    );
    try {
      return PriceHistory.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw _unreadable();
    } on FormatException {
      throw _unreadable();
    }
  }

  ApiException _unreadable() => const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
}

final productRepositoryProvider =
    Provider<ProductRepository>((ref) => ProductRepository(ref.watch(apiClientProvider)));
