import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../../core/api/view_state.dart';
import '../search/product_repository.dart';
import 'compare_models.dart';

class CompareState {
  const CompareState({
    this.sort = PriceSort.asc,
    this.view = const ViewLoading<ProductComparison>(),
  });

  final PriceSort sort;
  final ViewState<ProductComparison> view;
}

/// One product's price comparison: loads it and re-asks the server when the
/// order is switched.
class CompareController extends Notifier<CompareState> {
  CompareController(this.productId);

  final int productId;

  int _ticket = 0;

  @override
  CompareState build() {
    Future<void>.microtask(load);
    return const CompareState();
  }

  /// First load and "Bandyti dar kartą".
  Future<void> load() async {
    final ticket = ++_ticket;
    final sort = state.sort;
    state = CompareState(sort: sort);

    ViewState<ProductComparison> view;
    try {
      final comparison = await ref.read(productRepositoryProvider).productPrices(productId, sort);
      view = ViewSuccess(comparison);
    } on ApiException catch (e) {
      view = ViewError(e.userMessage);
    } catch (_) {
      view = const ViewError<ProductComparison>(messageForUnknown);
    }

    // The order was switched again meanwhile: this answer is stale.
    if (ref.mounted && ticket == _ticket) {
      state = CompareState(sort: sort, view: view);
    }
  }

  void setSort(PriceSort sort) {
    if (sort == state.sort) {
      return;
    }
    state = CompareState(sort: sort);
    load();
  }
}

final compareControllerProvider = NotifierProvider.autoDispose
    .family<CompareController, CompareState, int>(CompareController.new);
