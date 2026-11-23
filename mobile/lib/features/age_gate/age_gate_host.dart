import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'age_gate_controller.dart';
import 'age_gate_dialog.dart';

/// Shows the age dialog once when the app opens and the age is still unknown.
class AgeGateHost extends ConsumerStatefulWidget {
  const AgeGateHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AgeGateHost> createState() => _AgeGateHostState();
}

class _AgeGateHostState extends ConsumerState<AgeGateHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(ageGateProvider) == AgeStatus.unknown) {
        showAgeGateDialog(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows [child] only when the age is confirmed; otherwise explains why the
/// screen is unavailable and offers to answer the question again.
class AgeGuard extends ConsumerWidget {
  const AgeGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(ageGateProvider) == AgeStatus.confirmed) {
      return child;
    }

    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Kainų informacija nepasiekiama',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Alkoholinių gėrimų kainos rodomos tik asmenims, kuriems yra '
              '20 metų ar daugiau. Jei jums yra 20 metų ar daugiau, '
              'patvirtinkite savo amžių.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showAgeGateDialog(context),
              child: const Text('Patvirtinti amžių'),
            ),
          ],
        ),
      ),
    );
  }
}
