import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../age_gate/age_gate_host.dart';
import '../submit_price/open_submit_price.dart';
import '../submit_price/submit_price_models.dart';
import 'add_product_controller.dart';
import 'add_product_models.dart';
import 'volume_input.dart';

/// "Pridėti produktą": a signed-in user adds a missing product with its volume
/// and first price. Pops with `true` once the server has saved it.
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, required this.target});

  final AddProductTarget target;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _name = TextEditingController();
  final _volume = TextEditingController();
  final _price = TextEditingController();
  VolumeUnit _unit = VolumeUnit.ml;

  int get _key => widget.target.storeId;

  @override
  void dispose() {
    _name.dispose();
    _volume.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(addProductControllerProvider(_key).notifier).submit(
          rawName: _name.text,
          rawVolume: _volume.text,
          unit: _unit,
          rawPrice: _price.text,
        );
  }

  /// "Toks produktas jau yra": offers the price form of the existing product.
  Future<void> _askAboutDuplicate(ProductRef existing) async {
    final controller = ref.read(addProductControllerProvider(_key).notifier);

    final update = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Produktas jau yra'),
        content: Text(
          'Toks produktas jau yra: ${existing.name}, ${existing.volumeMl} ml. '
          'Norite atnaujinti jo kainą?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Atšaukti'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Atnaujinti kainą'),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }
    controller.dismissDuplicate();
    if (update ?? false) {
      final saved = await openSubmitPrice(
        context,
        ref,
        SubmitPriceTarget(
          productId: existing.id,
          productName: existing.name,
          volumeMl: existing.volumeMl,
          storeId: widget.target.storeId,
          storeName: widget.target.storeName,
        ),
      );
      if (saved && mounted) {
        Navigator.of(context).maybePop(true); // the screen before reloads
      }
    }
  }

  void _onSaved(CreatedProduct created) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Produktas pridėtas: ${created.product.name}, ${created.product.volumeMl} ml, '
          '${formatPrice(created.price.priceCents)}',
        ),
      ),
    );
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = addProductControllerProvider(_key);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final theme = Theme.of(context);
    final busy = state.isSubmitting;

    ref.listen<AddProductState>(provider, (previous, next) {
      if (next.phase == AddProductPhase.duplicate && previous?.phase != AddProductPhase.duplicate) {
        _askAboutDuplicate(next.existing!);
      }
      // Success is shown only after the server said so.
      if (next.phase == AddProductPhase.succeeded && previous?.phase != AddProductPhase.succeeded) {
        _onSaved(next.result!);
      }
    });

    final failure = state.failure;

    return AppScaffold(
      title: 'Pridėti produktą',
      body: AgeGuard(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Laukai, pažymėti *, yra privalomi.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !busy,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(maxProductNameLength)],
              onChanged: (_) => controller.onEdited(),
              decoration: InputDecoration(
                labelText: 'Pavadinimas *',
                hintText: 'Pavyzdžiui, Švyturys Ekstra',
                errorText: state.nameError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _volume,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(9),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => controller.onEdited(),
              decoration: InputDecoration(
                labelText: 'Talpa *',
                hintText: _unit == VolumeUnit.ml ? 'Pavyzdžiui, 500' : 'Pavyzdžiui, 0,5',
                helperText: 'Sveikas ml skaičius (1–50 000). Litrus galima rašyti su kableliu.',
                helperMaxLines: 2,
                errorText: state.volumeError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<VolumeUnit>(
                segments: [
                  for (final unit in VolumeUnit.values)
                    ButtonSegment(value: unit, label: Text(unit.label)),
                ],
                selected: {_unit},
                onSelectionChanged: busy
                    ? null
                    : (selection) {
                        setState(() => _unit = selection.single);
                        controller.onEdited();
                      },
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Parduotuvė',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              child: Text(widget.target.storeName, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(9),
              ],
              // Done on the keyboard does not send: only "Patvirtinti" does.
              textInputAction: TextInputAction.done,
              onChanged: (_) => controller.onEdited(),
              decoration: InputDecoration(
                labelText: 'Kaina, € *',
                hintText: 'Pavyzdžiui, 1,99',
                helperText: 'Vienos pakuotės kaina be užstato. Galima rašyti kablelį arba tašką.',
                helperMaxLines: 2,
                errorText: state.priceError,
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
