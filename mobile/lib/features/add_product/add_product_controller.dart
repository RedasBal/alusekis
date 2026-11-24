import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../submit_price/submit_price_models.dart';
import 'add_product_models.dart';
import 'add_product_repository.dart';
import 'volume_input.dart';

enum AddProductPhase {
  /// The user is typing; nothing has been sent (or the last attempt was cancelled).
  editing,

  /// A request is on its way; the confirm button is disabled.
  submitting,

  /// The server already has this product (same name and volume).
  duplicate,

  /// The last attempt failed; nothing was saved as far as the app knows.
  failed,

  /// The server confirmed the product. Only ever set from a server success.
  succeeded,
}

class AddProductState {
  const AddProductState({
    this.phase = AddProductPhase.editing,
    this.nameError,
    this.volumeError,
    this.priceError,
    this.failure,
    this.canRetry = false,
    this.showProgress = false,
    this.existing,
    this.result,
  });

  final AddProductPhase phase;

  /// Shown next to the matching field.
  final String? nameError;
  final String? volumeError;
  final String? priceError;

  /// A general message (no technical details).
  final String? failure;

  /// "Bandyti dar kartą" is offered (lost connection, server trouble).
  final bool canRetry;

  /// Set once a request has taken longer than a second.
  final bool showProgress;

  /// The product the server already has, for [AddProductPhase.duplicate].
  final ProductRef? existing;

  final CreatedProduct? result;

  bool get isSubmitting => phase == AddProductPhase.submitting;

  bool get hasFieldError => nameError != null || volumeError != null || priceError != null;
}

/// One filled-in form, as it will be sent.
typedef _Draft = ({String name, int volumeMl, int priceCents});

/// Creates one product with its first price in one store. The idempotency key
/// belongs to the content: retries reuse it, so a double tap or a retry after a
/// lost answer can never create the product twice; changed content gets a new
/// key. There is no background queue: a failure is a failure.
class AddProductController extends Notifier<AddProductState> {
  AddProductController(this.storeId);

  /// The store of the first price.
  final int storeId;

  static const Duration progressDelay = Duration(seconds: 1);

  String? _idempotencyKey;
  String? _keyContent;
  _Draft? _draft;
  Timer? _progressTimer;

  @override
  AddProductState build() {
    ref.onDispose(() => _progressTimer?.cancel());
    return const AddProductState();
  }

  /// "Patvirtinti": checks the fields and sends them. Nothing is sent before this.
  Future<void> submit({
    required String rawName,
    required String rawVolume,
    required VolumeUnit unit,
    required String rawPrice,
  }) async {
    if (state.isSubmitting) {
      return; // a second tap while the first is on its way
    }
    final name = checkProductName(rawName);
    final volume = checkVolumeInput(rawVolume, unit);
    final price = checkPriceInput(rawPrice);
    if (name.name == null || volume.ml == null || price.cents == null) {
      state = AddProductState(
        nameError: name.error,
        volumeError: volume.error,
        priceError: price.error,
      );
      return;
    }

    final draft = (name: name.name!, volumeMl: volume.ml!, priceCents: price.cents!);
    final content = '${draft.name.toLowerCase()}|${draft.volumeMl}|${draft.priceCents}';
    if (_keyContent != content) {
      _idempotencyKey = newIdempotencyKey(); // other content, other key
      _keyContent = content;
    }
    await _send(draft);
  }

  /// "Bandyti dar kartą": the same request with the same key.
  Future<void> retry() async {
    final draft = _draft;
    if (draft != null) {
      await _send(draft);
    }
  }

  /// The duplicate dialog was closed: back to editing.
  void dismissDuplicate() => state = const AddProductState();

  /// The user typed: old messages no longer apply.
  void onEdited() {
    if (state.hasFieldError || state.failure != null) {
      state = const AddProductState();
    }
  }

  Future<void> _send(_Draft draft) async {
    if (state.isSubmitting) {
      return;
    }
    _draft = draft;
    state = const AddProductState(phase: AddProductPhase.submitting);
    _progressTimer?.cancel();
    _progressTimer = Timer(progressDelay, () {
      if (ref.mounted && state.isSubmitting) {
        state = const AddProductState(phase: AddProductPhase.submitting, showProgress: true);
      }
    });

    AddProductState next;
    try {
      final created = await ref.read(addProductRepositoryProvider).create(
            name: draft.name,
            volumeMl: draft.volumeMl,
            storeId: storeId,
            priceCents: draft.priceCents,
            idempotencyKey: _idempotencyKey!,
          );
      next = AddProductState(phase: AddProductPhase.succeeded, result: created);
    } on ProductExistsException catch (e) {
      next = AddProductState(phase: AddProductPhase.duplicate, existing: e.existing);
    } on ApiException catch (e) {
      next = _failureFor(e.error);
    } catch (_) {
      next = const AddProductState(
        phase: AddProductPhase.failed,
        failure: messageForUnknown,
        canRetry: true,
      );
    }

    _progressTimer?.cancel();
    if (ref.mounted) {
      state = next;
    }
  }

  AddProductState _failureFor(ApiError error) {
    if (error.code == 'price_invalid') {
      return AddProductState(priceError: error.userMessage);
    }
    final lostConnection =
        error.kind == ApiErrorKind.network || error.kind == ApiErrorKind.timeout;
    final serverTrouble = (error.statusCode ?? 0) >= 500;
    return AddProductState(
      phase: AddProductPhase.failed,
      failure: lostConnection
          ? 'Nepavyko išsaugoti: nėra ryšio su serveriu. Produktas nepridėtas.'
          : error.userMessage,
      canRetry: lostConnection || serverTrouble,
    );
  }
}

final addProductControllerProvider = NotifierProvider.autoDispose
    .family<AddProductController, AddProductState, int>(AddProductController.new);
