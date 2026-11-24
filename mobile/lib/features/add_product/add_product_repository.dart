import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'add_product_models.dart';

/// `POST /products`. Signed-in users only; the server checks the role.
class AddProductRepository {
  AddProductRepository(this._api);

  final ApiClient _api;

  /// Sends one creation. Throws [ProductExistsException] when the server already
  /// has the product, otherwise [ApiException] on failure.
  ///
  /// Retries of the same creation must reuse [idempotencyKey].
  Future<CreatedProduct> create({
    required String name,
    required int volumeMl,
    required int storeId,
    required int priceCents,
    required String idempotencyKey,
  }) async {
    final dynamic data;
    try {
      data = await _api.post(
        '/products',
        body: {
          'name': name,
          'volumeMl': volumeMl,
          'storeId': storeId,
          'priceCents': priceCents,
          'idempotencyKey': idempotencyKey,
        },
      );
    } on ApiException catch (e) {
      final existing = e.error.body?['existingProduct'];
      if (e.error.code == 'product_exists' && existing is Map<String, dynamic>) {
        throw ProductExistsException(ProductRef.fromJson(existing));
      }
      rethrow;
    }

    try {
      return CreatedProduct.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }
}

final addProductRepositoryProvider = Provider<AddProductRepository>(
  (ref) => AddProductRepository(ref.watch(apiClientProvider)),
);
