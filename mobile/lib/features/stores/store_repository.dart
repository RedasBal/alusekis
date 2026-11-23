import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'store_models.dart';
import 'store_prices_models.dart';

/// Reads cities and stores from the server. Guests may call these endpoints.
class StoreRepository {
  StoreRepository(this._api);

  final ApiClient _api;

  Future<List<City>> cities() async =>
      _items(await _api.get('/cities'), City.fromJson);

  Future<List<StoreItem>> byCity(int cityId) async => _items(
        await _api.get('/stores', queryParameters: {'cityId': cityId}),
        StoreItem.fromJson,
      );

  /// [origin] is sent for this one request only; it is not stored or logged.
  Future<List<StoreItem>> nearby(GeoPoint origin, int radiusKm) async => _items(
        await _api.get(
          '/stores',
          queryParameters: {
            'lat': origin.latitude,
            'lng': origin.longitude,
            'radiusKm': radiusKm,
          },
        ),
        StoreItem.fromJson,
      );

  Future<StorePricesPage> storePrices(int storeId, int page, int pageSize) async {
    final data = await _api.get(
      '/stores/$storeId/prices',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    try {
      return StorePricesPage.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }

  List<T> _items<T>(dynamic data, T Function(Map<String, dynamic>) parse) {
    try {
      final items = (data as Map<String, dynamic>)['items'] as List<dynamic>;
      return [for (final item in items) parse(item as Map<String, dynamic>)];
    } on TypeError {
      throw const ApiException(
        ApiError(kind: ApiErrorKind.unknown, userMessage: messageForUnknown),
      );
    }
  }
}

final storeRepositoryProvider =
    Provider<StoreRepository>((ref) => StoreRepository(ref.watch(apiClientProvider)));

final citiesProvider =
    FutureProvider<List<City>>((ref) => ref.watch(storeRepositoryProvider).cities());
