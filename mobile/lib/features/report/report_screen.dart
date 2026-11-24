import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../age_gate/age_gate_host.dart';
import 'report_controller.dart';
import 'report_models.dart';

/// Shown after the server stored the report: says what happens next.
const String reportSentMessage =
    'Pranešimas pateiktas. Kaina nebus pakeista iškart – administratorius ją patikrins.';

/// "Pranešti apie klaidą": a signed-in user reports a doubtful price. Pops
/// with `true` once the server has stored the report. The price is not changed.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.target});

  final ReportTarget target;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _comment = TextEditingController();
  ReportReason? _reason;

  int get _key => widget.target.priceEntryId;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _submit() => ref.read(reportControllerProvider(_key).notifier).submit(_reason, _comment.text);

  void _onSent() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(reportSentMessage), duration: Duration(seconds: 6)),
    );
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = reportControllerProvider(_key);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final theme = Theme.of(context);
    final target = widget.target;
    final busy = state.isSubmitting;
    final commentRequired = _reason == ReportReason.other;

    ref.listen<ReportState>(provider, (previous, next) {
      // Success is shown only after the server said so.
      if (next.phase == ReportPhase.succeeded && previous?.phase != ReportPhase.succeeded) {
        _onSent();
      }
    });

    final failure = state.failure;

    return AppScaffold(
      title: 'Pranešti apie klaidą',
      body: AgeGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PriceContext(target: target),
            const SizedBox(height: 16),
            Text(
              'Pranešimas nekeičia kainos ir jos nepašalina. Administratorius patikrins įrašą vėliau.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Laukai, pažymėti *, yra privalomi.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('Priežastis *', style: theme.textTheme.titleMedium),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!busy) {
                  setState(() => _reason = value);
                  controller.onEdited();
                }
              },
              child: Column(
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: reason,
                      enabled: !busy,
                      title: Text(reason.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            if (state.reasonError != null) _FieldError(message: state.reasonError!),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              maxLength: maxReportCommentLength,
              // Longer text can be pasted; the form then explains the limit.
              maxLengthEnforcement: MaxLengthEnforcement.none,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => controller.onEdited(),
              decoration: InputDecoration(
                labelText: commentRequired ? 'Komentaras *' : 'Komentaras (neprivalomas)',
                helperText: 'Privalomas pasirinkus „Kita“.',
                errorText: state.commentError,
                errorMaxLines: 2,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: 16),
              _FailureBanner(
                message: failure,
                onRetry: state.canRetry ? controller.retry : null,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => Navigator.of(context).maybePop(false),
                    child: const Text('Atšaukti'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : _submit,
                    child: state.showProgress
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Siunčiama…'),
                            ],
                          )
                        : const Text('Pateikti'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The price being reported, so the user knows what the report is about.
class _PriceContext extends StatelessWidget {
  const _PriceContext({required this.target});

  final ReportTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(target.productName, style: theme.textTheme.titleMedium),
                  Text('${target.volumeMl} ml', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.storefront_outlined, size: 18),
                      const SizedBox(width: 6),
                      Expanded(child: Text(target.storeName, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Patikrinta: ${formatDateTime(target.observedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(formatPrice(target.priceCents), style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

/// An error under a field that is not a text field: an icon and words, not colour alone.
class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
              ],
            ),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRetry, child: const Text('Bandyti dar kartą')),
              ),
          ],
        ),
      ),
    );
  }
}
