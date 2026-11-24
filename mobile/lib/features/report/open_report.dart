import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/routes.dart';
import 'report_models.dart';

/// Opens "Pranešti apie klaidą" for [target]. A user who is not signed in is
/// sent to sign in first and, once signed in, comes straight back to the form.
/// Resolves to true when the server stored the report.
///
/// This only decides where to go; whether the user may report is checked by the server.
Future<bool> openReport(BuildContext context, WidgetRef ref, ReportTarget target) async {
  if (!ref.read(authControllerProvider).isSignedIn) {
    await context.push<void>(Routes.signIn);
    if (!context.mounted || !ref.read(authControllerProvider).isSignedIn) {
      return false; // the user left the sign-in without signing in
    }
  }

  final sent = await context.push<bool>(Routes.reportPrice(target.priceEntryId), extra: target);
  return sent ?? false;
}

/// The "Pranešti apie klaidą" button on a price row. Disabled with a short
/// reason when there is no connection to the server.
class ReportButton extends StatelessWidget {
  const ReportButton({super.key, required this.onPressed, this.offline = false});

  final VoidCallback onPressed;

  /// The screen is showing saved data because the server cannot be reached.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: offline ? null : onPressed,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Pranešti apie klaidą'),
        ),
        if (offline)
          Text(
            'Be ryšio pranešti negalima',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
