import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_error.dart';

/// The four states every data screen distinguishes.
sealed class ViewState<T> {
  const ViewState();
}

/// Data is being loaded.
class ViewLoading<T> extends ViewState<T> {
  const ViewLoading();
}

/// Loading failed; [message] is Lithuanian and safe to show.
class ViewError<T> extends ViewState<T> {
  const ViewError(this.message);

  final String message;
}

/// Loading succeeded but there is nothing to show.
class ViewEmpty<T> extends ViewState<T> {
  const ViewEmpty();
}

/// Loading succeeded with [data].
class ViewSuccess<T> extends ViewState<T> {
  const ViewSuccess(this.data);

  final T data;
}

extension AsyncValueViewState<T> on AsyncValue<T> {
  /// Maps a Riverpod [AsyncValue] to a [ViewState]. [isEmpty] decides when a
  /// successful value counts as "empty" (defaults to empty collections / null).
  ViewState<T> toViewState({bool Function(T value)? isEmpty}) {
    return when(
      loading: () => ViewLoading<T>(),
      error: (error, _) => ViewError<T>(
        error is ApiException
            ? error.userMessage
            : 'Įvyko netikėta klaida. Bandykite vėliau.',
      ),
      data: (value) {
        final empty = isEmpty?.call(value) ?? _defaultIsEmpty(value);
        return empty ? ViewEmpty<T>() : ViewSuccess<T>(value);
      },
    );
  }
}

bool _defaultIsEmpty(Object? value) =>
    value == null || (value is Iterable && value.isEmpty);
