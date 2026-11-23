import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/view_state.dart';
import '../../core/utils/clock.dart';
import 'store_prices_cache.dart';
import 'store_prices_models.dart';
import 'store_repository.dart';

/// Shown when the server cannot be reached and nothing was saved for the store.
const String messageNoConnectionNoCache =
    'Nėra ryšio su serveriu, o šios parduotuvės kainų įrenginyje išsaugota nėra. '
    'Patikrinkite interneto ryšį ir bandykite dar kartą.';

class StorePricesData {
  const StorePricesData({
    required this.store,
    required this.items,
    required this.total,
    required this.loadedPages,
    this.cachedAt,
  });

  final StoreSummary store;
  final List<StorePrice> items;
  final int total;
  final int loadedPages;

  /// Set when these are saved data (sync time, UTC) instead of a fresh answer.
  final DateTime? cachedAt;

  bool get isFromCache => cachedAt != null;

  /// More pages can only be fetched while the data are live.
  bool get hasMore => !isFromCache && items.length < total;
}

class StorePricesState {
  const StorePricesState({
    this.view = const ViewLoading<StorePricesData>(),
    this.loadingMore = false,
    this.moreError,
  });

  final ViewState<StorePricesData> view;
  final bool loadingMore;

  /// Why the last "Rodyti daugiau" failed (Lithuanian, no technical detail).
  final String? moreError;
}

/// Prices of one store: loads page by page, keeps the last good answer on the
/// device and falls back to it when the server cannot be used.
class StorePricesController extends Notifier<StorePricesState> {
  StorePricesController(this.storeId);

  final int storeId;

  static const int pageSize = 20;

  int _ticket = 0;

  @override
  StorePricesState build() {
    Future<void>.microtask(load);
    return const StorePricesState();
  }

  /// First page (also "Bandyti dar kartą").
  Future<void> load() async {
    final ticket = ++_ticket;
    state = const StorePricesState();

    ViewState<StorePricesData> view;
    try {
      final page = await ref.read(storeRepositoryProvider).storePrices(storeId, 1, pageSize);
      final data = StorePricesData(
        store: page.store,
        items: page.items,
        total: page.total,
        loadedPages: 1,
      );
      await _save(data);
      view = ViewSuccess(data);
    } on ApiException catch (e) {
      view = _fallback(e);
    } catch (_) {
      view = const ViewError<StorePricesData>('Įvyko netikėta klaida. Bandykite vėliau.');
    }

    if (_isCurrent(ticket)) {
      state = StorePricesState(view: view);
    }
  }

  /// "Rodyti daugiau": appends the next page to the live data.
  Future<void> loadMore() async {
    final view = state.view;
    if (view is! ViewSuccess<StorePricesData> || !view.data.hasMore || state.loadingMore) {
      return;
    }

    final ticket = _ticket;
    final current = view.data;
    state = StorePricesState(view: view, loadingMore: true);

    try {
      final page = await ref
          .read(storeRepositoryProvider)
          .storePrices(storeId, current.loadedPages + 1, pageSize);

      // Rows may shift between requests; never show a price entry twice.
      final known = {for (final item in current.items) item.priceEntryId};
      final data = StorePricesData(
        store: current.store,
        items: [
          ...current.items,
          ...page.items.where((item) => !known.contains(item.priceEntryId)),
        ],
        total: page.total,
        loadedPages: current.loadedPages + 1,
      );
      await _save(data);
      if (_isCurrent(ticket)) {
        state = StorePricesState(view: ViewSuccess(data));
      }
    } on ApiException catch (e) {
      if (_isCurrent(ticket)) {
        state = StorePricesState(view: view, moreError: e.userMessage);
      }
    } catch (_) {
      if (_isCurrent(ticket)) {
        state = StorePricesState(
          view: view,
          moreError: 'Įvyko netikėta klaida. Bandykite vėliau.',
        );
      }
    }
  }

  bool _isCurrent(int ticket) => ref.mounted && ticket == _ticket;

  /// Saved data if there are any (not for a store the server says is gone),
  /// otherwise an error message that says what is wrong.
  ViewState<StorePricesData> _fallback(ApiException error) {
    final snapshot = error.error.statusCode == 404
        ? null
        : ref.read(storePricesCacheProvider).read(storeId);

    if (snapshot != null) {
      return ViewSuccess(
        StorePricesData(
          store: snapshot.store,
          items: markStaleByDeviceClock(snapshot.items, ref.read(nowProvider)()),
          total: snapshot.total,
          loadedPages: 1,
          cachedAt: snapshot.syncedAt,
        ),
      );
    }

    final offline = error.error.kind == ApiErrorKind.network ||
        error.error.kind == ApiErrorKind.timeout;
    return ViewError(offline ? messageNoConnectionNoCache : error.userMessage);
  }

  Future<void> _save(StorePricesData data) async {
    try {
      await ref.read(storePricesCacheProvider).write(
            storeId,
            PricesSnapshot(
              store: data.store,
              items: data.items,
              total: data.total,
              syncedAt: ref.read(nowProvider)(),
            ),
          );
    } catch (error) {
      // The cache is a convenience; failing to write it must not break the screen.
      debugPrint('Price cache not saved: ${error.runtimeType}');
    }
  }
}

final storePricesControllerProvider = NotifierProvider.autoDispose
    .family<StorePricesController, StorePricesState, int>(StorePricesController.new);
