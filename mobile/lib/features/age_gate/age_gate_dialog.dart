import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'age_gate_controller.dart';

/// Opens the age question. It cannot be dismissed without an answer.
Future<void> showAgeGateDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AgeGateDialog(),
    );

class AgeGateDialog extends ConsumerWidget {
  const AgeGateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Ar jums yra 20 metų ar daugiau?'),
        content: const Text(
          'Programėlėje rodomos alkoholinių gėrimų kainos, todėl '
          'reikalingas amžiaus patvirtinimas.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(ageGateProvider.notifier).decline();
              Navigator.of(context).pop();
            },
            child: const Text('Ne'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(ageGateProvider.notifier).confirm();
              Navigator.of(context).pop();
            },
            child: const Text('Taip'),
          ),
        ],
      ),
    );
  }
}
