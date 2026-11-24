import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/routes.dart';
import 'submit_price_models.dart';

/// Opens "Atnaujinti kainą" for [target]. A user who is not signed in is sent
/// to sign in first and, once signed in, comes straight back to the form.
/// Resolves to true when the server saved a price (the caller then reloads).
///
/// This only decides where to go; whether the user may submit is checked by
/// the server.
Future<bool> openSubmitPrice(BuildContext context, WidgetRef ref, SubmitPriceTarget target) async {
  if (!ref.read(authControllerProvider).isSignedIn) {
    await context.push<void>(Routes.signIn);
    if (!context.mounted || !ref.read(authControllerProvider).isSignedIn) {
      return false; // the user left the sign-in without signing in
    }
  }

  final saved = await context.push<bool>(
    Routes.submitPrice(target.productId, target.storeId),
    extra: target,
  );
  return saved ?? false;
}

/// The "Atnaujinti kainą" button used on price rows. Disabled with a short
/// reason when there is no connection to the server.
class SubmitPriceButton extends StatelessWidget {
  const SubmitPriceButton({super.key, required this.onPressed, this.offline = false});

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
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Atnaujinti kainą'),
        ),
        if (offline)
          Text(
            'Be ryšio kainos atnaujinti negalima',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
