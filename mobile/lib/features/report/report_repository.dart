import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'report_models.dart';

/// `POST /reports`. Signed-in users only; the server checks the role.
class ReportRepository {
  ReportRepository(this._api);

  final ApiClient _api;

  /// Sends one report. Throws [ApiException] on failure.
  ///
  /// Retries of the same report must reuse [idempotencyKey], so the server
  /// answers them again instead of storing the report twice.
  Future<SubmittedReport> submit({
    required int priceEntryId,
    required ReportReason reason,
    required String? comment,
    required String idempotencyKey,
  }) async {
    final dynamic data = await _api.post(
      '/reports',
      body: {
        'priceEntryId': priceEntryId,
        'reason': reason.apiName,
        'comment': ?comment,
        'idempotencyKey': idempotencyKey,
      },
    );

    try {
      return SubmittedReport.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(apiClientProvider)),
);
