import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../age_gate/age_gate_host.dart';
import 'submit_price_controller.dart';
import 'submit_price_models.dart';

/// "Atnaujinti kainą": a signed-in user records a checked price. Pops with
/// `true` once the server has saved it.
class SubmitPriceScreen extends ConsumerStatefulWidget {
  const SubmitPriceScreen({super.key, required this.target});

  final SubmitPriceTarget target;

  @override
  ConsumerState<SubmitPriceScreen> createState() => _SubmitPriceScreenState();
}

class _SubmitPriceScreenState extends ConsumerState<SubmitPriceScreen> {
  final _price = TextEditingController();

  SubmitPriceKey get _key => (widget.target.productId, widget.target.storeId);

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _askToConfirm(SubmitPriceState state) async {
    final controller = ref.read(submitPriceControllerProvider(_key).notifier);
    final previous = formatPrice(state.previousPriceCents!);
    final current = formatPrice(state.attemptedCents!);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Patvirtinkite kainą'),
        content: Text(
          'Kaina skiriasi nuo ankstesnės (buvo $previous, dabar $current). '
          'Ar tikrai norite išsaugoti?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Atšaukti'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Patvirtinti'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    if (confirmed ?? false) {
      await controller.confirmLargeChange();
    } else {
      controller.cancelLargeChange();
    }
  }

  void _onSaved(SubmittedPrice saved) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kaina išsaugota: ${formatPrice(saved.priceCents)}')),
    );
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = submitPriceControllerProvider(_key);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final theme = Theme.of(context);
    final target = widget.target;

    ref.listen<SubmitPriceState>(provider, (previous, next) {
      if (next.phase == SubmitPhase.needsConfirmation &&
          previous?.phase != SubmitPhase.needsConfirmation) {
        _askToConfirm(next);
      }
      // Success is shown only after the server said so.
      if (next.phase == SubmitPhase.succeeded && previous?.phase != SubmitPhase.succeeded) {
        _onSaved(next.result!);
      }
    });

    final failure = state.failure;

    return AppScaffold(
      title: 'Atnaujinti kainą',
      body: AgeGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(target.productName, style: theme.textTheme.titleLarge),
            Text('${target.volumeMl} ml', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(target.storeName, style: theme.textTheme.bodyLarge)),
              ],
            ),
            if (target.currentPriceCents != null) ...[
              const SizedBox(height: 8),
              Text(
                'Dabartinė kaina: ${formatPrice(target.currentPriceCents!)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _price,
              enabled: !state.isSubmitting,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(9),
              ],
              // Done on the keyboard does not send: only "Patvirtinti" does.
              textInputAction: TextInputAction.done,
              onChanged: (_) => controller.onPriceEdited(),
              decoration: InputDecoration(
                labelText: 'Kaina, €',
                hintText: 'Pavyzdžiui, 1,99',
                helperText: 'Vienos pakuotės kaina be užstato. Galima rašyti kablelį arba tašką.',
                helperMaxLines: 2,
                errorText: state.fieldError,
                errorMaxLines: 2,
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
                    onPressed: state.isSubmitting ? null : () => Navigator.of(context).maybePop(false),
                    child: const Text('Atšaukti'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: state.isSubmitting ? null : () => controller.submit(_price.text),
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
                        : const Text('Patvirtinti'),
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
