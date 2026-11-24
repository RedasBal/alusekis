import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../submit_price/submit_price_models.dart';
import 'report_models.dart';
import 'report_repository.dart';

enum ReportPhase {
  /// The user is filling in the form; nothing has been sent.
  editing,

  /// A request is on its way; the submit button is disabled.
  submitting,

  /// The last attempt failed; nothing was stored as far as the app knows.
  failed,

  /// The server confirmed the report. Only ever set from a server success.
  succeeded,
}

class ReportState {
  const ReportState({
    this.phase = ReportPhase.editing,
    this.reasonError,
    this.commentError,
    this.failure,
    this.canRetry = false,
    this.showProgress = false,
    this.result,
  });

  final ReportPhase phase;

  /// Shown next to the matching field.
  final String? reasonError;
  final String? commentError;

  /// A general message (no technical details).
  final String? failure;

  /// "Bandyti dar kartą" is offered (lost connection, server trouble).
  final bool canRetry;

  /// Set once a request has taken longer than a second.
  final bool showProgress;

  final SubmittedReport? result;

  bool get isSubmitting => phase == ReportPhase.submitting;

  bool get hasFieldError => reasonError != null || commentError != null;
}

typedef _Draft = ({ReportReason reason, String? comment});

/// Sends one report about one price entry. The idempotency key belongs to the
/// content: retries reuse it, so a retry after a lost answer can never store
/// the report twice; changed content gets a new key. No background queue.
class ReportController extends Notifier<ReportState> {
  ReportController(this.priceEntryId);

  final int priceEntryId;

  static const Duration progressDelay = Duration(seconds: 1);

  String? _idempotencyKey;
  String? _keyContent;
  _Draft? _draft;
  Timer? _progressTimer;

  @override
  ReportState build() {
    ref.onDispose(() => _progressTimer?.cancel());
    return const ReportState();
  }

  /// "Pateikti": checks the form and sends it. Nothing is sent before this.
  Future<void> submit(ReportReason? reason, String rawComment) async {
    if (state.isSubmitting) {
      return; // a second tap while the first is on its way
    }
    final input = checkReportInput(reason, rawComment);
    if (!input.isValid) {
      state = ReportState(reasonError: input.reasonError, commentError: input.commentError);
      return;
    }

    final draft = (reason: input.reason!, comment: input.comment);
    final content = '${draft.reason.apiName}|${draft.comment ?? ''}';
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

  /// The user changed the form: old messages no longer apply.
  void onEdited() {
    if (state.hasFieldError || state.failure != null) {
      state = const ReportState();
    }
  }

  Future<void> _send(_Draft draft) async {
    if (state.isSubmitting) {
      return;
    }
    _draft = draft;
    state = const ReportState(phase: ReportPhase.submitting);
    _progressTimer?.cancel();
    _progressTimer = Timer(progressDelay, () {
      if (ref.mounted && state.isSubmitting) {
        state = const ReportState(phase: ReportPhase.submitting, showProgress: true);
      }
    });

    ReportState next;
    try {
      final saved = await ref.read(reportRepositoryProvider).submit(
            priceEntryId: priceEntryId,
            reason: draft.reason,
            comment: draft.comment,
            idempotencyKey: _idempotencyKey!,
          );
      next = ReportState(phase: ReportPhase.succeeded, result: saved);
    } on ApiException catch (e) {
      next = _failureFor(e.error);
    } catch (_) {
      next = const ReportState(
        phase: ReportPhase.failed,
        failure: messageForUnknown,
        canRetry: true,
      );
    }

    _progressTimer?.cancel();
    if (ref.mounted) {
      state = next;
    }
  }

  ReportState _failureFor(ApiError error) {
    final lostConnection =
        error.kind == ApiErrorKind.network || error.kind == ApiErrorKind.timeout;
    final serverTrouble = (error.statusCode ?? 0) >= 500;
    return ReportState(
      phase: ReportPhase.failed,
      failure: lostConnection
          ? 'Nepavyko pateikti: nėra ryšio su serveriu. Pranešimas nepateiktas.'
          : error.userMessage,
      canRetry: lostConnection || serverTrouble,
    );
  }
}

final reportControllerProvider =
    NotifierProvider.autoDispose.family<ReportController, ReportState, int>(ReportController.new);
