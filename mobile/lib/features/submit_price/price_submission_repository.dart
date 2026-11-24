import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'submit_price_models.dart';

/// `POST /prices`. Signed-in users only; the server checks the role.
class PriceSubmissionRepository {
  PriceSubmissionRepository(this._api);

  final ApiClient _api;

  /// Sends one submission. Throws [LargePriceChangeException] when the server
  /// asks for confirmation, otherwise [ApiException] on failure.
  ///
  /// Retries of the same submission must reuse [idempotencyKey], so the server
  /// answers them again instead of recording the price twice.
  Future<SubmittedPrice> submit({
    required int productId,
    required int storeId,
    required int priceCents,
    required String idempotencyKey,
    required bool confirmLargeChange,
  }) async {
    final dynamic data;
    try {
      data = await _api.post(
        '/prices',
        body: {
          'productId': productId,
          'storeId': storeId,
          'priceCents': priceCents,
          'idempotencyKey': idempotencyKey,
          'confirmLargeChange': confirmLargeChange,
        },
      );
    } on ApiException catch (e) {
      final previous = e.error.body?['previousPriceCents'];
      if (e.error.code == 'large_price_change' && previous is num) {
        throw LargePriceChangeException(previous.toInt());
      }
      rethrow;
    }

    try {
      return SubmittedPrice.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }
}

final priceSubmissionRepositoryProvider = Provider<PriceSubmissionRepository>(
  (ref) => PriceSubmissionRepository(ref.watch(apiClientProvider)),
);
