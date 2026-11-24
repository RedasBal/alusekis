import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import 'price_submission_repository.dart';
import 'submit_price_models.dart';

enum SubmitPhase {
  /// The user is typing; nothing has been sent (or the last attempt was cancelled).
  editing,

  /// A request is on its way; the confirm button is disabled.
  submitting,

  /// The server asked to confirm a change of more than 50 %.
  needsConfirmation,

  /// The last attempt failed; nothing was saved as far as the app knows.
  failed,

  /// The server confirmed the price. Only ever set from a server success.
  succeeded,
}

class SubmitPriceState {
  const SubmitPriceState({
    this.phase = SubmitPhase.editing,
    this.fieldError,
    this.failure,
    this.canRetry = false,
    this.showProgress = false,
    this.attemptedCents,
    this.previousPriceCents,
    this.result,
  });

  final SubmitPhase phase;

  /// Shown next to the price field.
  final String? fieldError;

  /// A general message (no technical details).
  final String? failure;

  /// "Bandyti dar kartą" is offered (lost connection, server trouble).
  final bool canRetry;

  /// Set once a request has taken longer than a second.
  final bool showProgress;

  /// The price of the current attempt, in cents.
  final int? attemptedCents;

  /// The previous price the server reported for a large change.
  final int? previousPriceCents;

  final SubmittedPrice? result;

  bool get isSubmitting => phase == SubmitPhase.submitting;
}

/// (productId, storeId): one form per product in a store.
typedef SubmitPriceKey = (int productId, int storeId);

/// Submits one price. The idempotency key belongs to the content: retries and
/// the confirmation of a large change reuse it, so a double tap or a retry after
/// a lost answer can never record the price twice; a different price gets a
/// new key. There is no background queue: a failure is a failure.
class SubmitPriceController extends Notifier<SubmitPriceState> {
  SubmitPriceController(this.key);

  final SubmitPriceKey key;

  static const Duration progressDelay = Duration(seconds: 1);

  String? _idempotencyKey;
  int? _keyCents;
  bool _lastConfirm = false;
  Timer? _progressTimer;

  @override
  SubmitPriceState build() {
    ref.onDispose(() => _progressTimer?.cancel());
    return const SubmitPriceState();
  }

  /// "Patvirtinti": checks the field and sends it. Nothing is sent before this.
  Future<void> submit(String rawPrice) async {
    if (state.isSubmitting) {
      return; // a second tap while the first is on its way
    }
    final input = checkPriceInput(rawPrice);
    final cents = input.cents;
    if (cents == null) {
      state = SubmitPriceState(fieldError: input.error);
      return;
    }
    if (_keyCents != cents) {
      _idempotencyKey = newIdempotencyKey(); // other content, other key
      _keyCents = cents;
    }
    await _send(cents, confirm: false);
  }

  /// The user accepted the large change: the same request again, confirmed.
  Future<void> confirmLargeChange() async {
    final cents = state.attemptedCents;
    if (cents != null) {
      await _send(cents, confirm: true);
    }
  }

  void cancelLargeChange() => state = const SubmitPriceState();

  /// "Bandyti dar kartą": the same request with the same key.
  Future<void> retry() async {
    final cents = _keyCents;
    if (cents != null) {
      await _send(cents, confirm: _lastConfirm);
    }
  }

  /// The user typed: old messages no longer apply.
  void onPriceEdited() {
    if (state.fieldError != null || state.failure != null) {
      state = const SubmitPriceState();
    }
  }

  Future<void> _send(int cents, {required bool confirm}) async {
    if (state.isSubmitting) {
      return;
    }
    _lastConfirm = confirm;
    state = SubmitPriceState(phase: SubmitPhase.submitting, attemptedCents: cents);
    _progressTimer?.cancel();
    _progressTimer = Timer(progressDelay, () {
      if (ref.mounted && state.isSubmitting) {
        state = SubmitPriceState(
          phase: SubmitPhase.submitting,
          attemptedCents: cents,
          showProgress: true,
        );
      }
    });

    SubmitPriceState next;
    try {
      final saved = await ref.read(priceSubmissionRepositoryProvider).submit(
            productId: key.$1,
            storeId: key.$2,
            priceCents: cents,
            idempotencyKey: _idempotencyKey!,
            confirmLargeChange: confirm,
          );
      next = SubmitPriceState(phase: SubmitPhase.succeeded, attemptedCents: cents, result: saved);
    } on LargePriceChangeException catch (e) {
      next = SubmitPriceState(
        phase: SubmitPhase.needsConfirmation,
        attemptedCents: cents,
        previousPriceCents: e.previousPriceCents,
      );
    } on ApiException catch (e) {
      next = _failureFor(e.error, cents);
    } catch (_) {
      next = SubmitPriceState(
        phase: SubmitPhase.failed,
        attemptedCents: cents,
        failure: messageForUnknown,
        canRetry: true,
      );
    }

    _progressTimer?.cancel();
    if (ref.mounted) {
      state = next;
    }
  }

  SubmitPriceState _failureFor(ApiError error, int cents) {
    if (error.code == 'price_invalid') {
      return SubmitPriceState(fieldError: error.userMessage, attemptedCents: cents);
    }
    final lostConnection =
        error.kind == ApiErrorKind.network || error.kind == ApiErrorKind.timeout;
    final serverTrouble = (error.statusCode ?? 0) >= 500;
    return SubmitPriceState(
      phase: SubmitPhase.failed,
      attemptedCents: cents,
      failure: lostConnection
          ? 'Nepavyko išsaugoti: nėra ryšio su serveriu. Kaina neišsaugota.'
          : error.userMessage,
      canRetry: lostConnection || serverTrouble,
    );
  }
}

final submitPriceControllerProvider = NotifierProvider.autoDispose
    .family<SubmitPriceController, SubmitPriceState, SubmitPriceKey>(SubmitPriceController.new);
