import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../../core/api/view_state.dart';
import '../../core/utils/debouncer.dart';
import 'product_models.dart';
import 'product_repository.dart';
import 'search_query.dart';

class ProductSearchState {
  const ProductSearchState({this.text = '', this.view});

  /// What is in the search field.
  final String text;

  /// Null while there is nothing to search for (text under 2 characters): the
  /// screen then shows the hint and no request was made.
  final ViewState<List<ProductSearchItem>>? view;
}

/// Search as you type: waits for a pause in typing, never sends a text that is
/// too short, and abandons the previous request when the text changes.
class ProductSearchController extends Notifier<ProductSearchState> {
  final Debouncer _debouncer = Debouncer(searchDebounce);
  CancelToken? _inFlight;
  int _ticket = 0;

  @override
  ProductSearchState build() {
    ref.onDispose(() {
      _debouncer.cancel();
      _inFlight?.cancel();
    });
    return const ProductSearchState();
  }

  /// Called on every change of the search field.
  void onTextChanged(String text) {
    _debouncer.cancel();

    if (!isSearchable(text)) {
      _abandonRequest();
      state = ProductSearchState(text: text); // hint, nothing is sent
      return;
    }

    // Keep the previous results on screen until the pause in typing ends.
    state = ProductSearchState(text: text, view: state.view);
    final query = searchText(text);
    _debouncer.run(() => _search(query));
  }

  /// "Bandyti dar kartą".
  Future<void> retry() {
    _debouncer.cancel();
    return _search(searchText(state.text));
  }

  Future<void> _search(String query) async {
    if (!isSearchable(query)) {
      return;
    }

    final ticket = ++_ticket;
    _inFlight?.cancel(); // the earlier request is no longer wanted
    final token = CancelToken();
    _inFlight = token;
    state = ProductSearchState(
      text: state.text,
      view: const ViewLoading<List<ProductSearchItem>>(),
    );

    ViewState<List<ProductSearchItem>> view;
    try {
      final items = await ref.read(productRepositoryProvider).search(query, cancelToken: token);
      view = items.isEmpty
          ? const ViewEmpty<List<ProductSearchItem>>()
          : ViewSuccess<List<ProductSearchItem>>(items);
    } on ApiException catch (e) {
      if (e.error.kind == ApiErrorKind.cancelled) {
        return; // replaced by a newer search
      }
      view = ViewError<List<ProductSearchItem>>(e.userMessage);
    } catch (_) {
      view = const ViewError<List<ProductSearchItem>>(messageForUnknown);
    }

    // An answer to a request that was replaced meanwhile is stale.
    if (ref.mounted && ticket == _ticket) {
      state = ProductSearchState(text: state.text, view: view);
    }
  }

  void _abandonRequest() {
    _ticket++;
    _inFlight?.cancel();
    _inFlight = null;
  }
}

final productSearchControllerProvider =
    NotifierProvider<ProductSearchController, ProductSearchState>(ProductSearchController.new);
