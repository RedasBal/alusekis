import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../../core/api/view_state.dart';
import '../search/product_repository.dart';
import 'history_models.dart';

class HistoryState {
  const HistoryState({
    this.period = HistoryPeriod.defaultPeriod,
    this.view = const ViewLoading<PriceHistory>(),
  });

  final HistoryPeriod period;
  final ViewState<PriceHistory> view;
}

/// (productId, storeId): a history belongs to one product in one store.
typedef HistoryKey = (int productId, int storeId);

/// The price history of one product in one store: loads it and loads again
/// when the period is changed.
class HistoryController extends Notifier<HistoryState> {
  HistoryController(this.key);

  final HistoryKey key;

  int _ticket = 0;

  @override
  HistoryState build() {
    Future<void>.microtask(load);
    return const HistoryState();
  }

  /// First load and "Bandyti dar kartą".
  Future<void> load() async {
    final ticket = ++_ticket;
    final period = state.period;
    state = HistoryState(period: period);

    ViewState<PriceHistory> view;
    try {
      final history = await ref
          .read(productRepositoryProvider)
          .productStoreHistory(key.$1, key.$2, period);
      view = ViewSuccess(history);
    } on ApiException catch (e) {
      view = ViewError(e.userMessage);
    } catch (_) {
      view = const ViewError<PriceHistory>(messageForUnknown);
    }

    // The period was changed again meanwhile: this answer is stale.
    if (ref.mounted && ticket == _ticket) {
      state = HistoryState(period: period, view: view);
    }
  }

  void setPeriod(HistoryPeriod period) {
    if (period == state.period) {
      return;
    }
    state = HistoryState(period: period);
    load();
  }
}

final historyControllerProvider = NotifierProvider.autoDispose
    .family<HistoryController, HistoryState, HistoryKey>(HistoryController.new);
