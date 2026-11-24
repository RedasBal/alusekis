import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/routes.dart';
import 'add_product_models.dart';

/// Opens "Pridėti produktą" for [target]. A user who is not signed in is sent
/// to sign in first and, once signed in, comes straight back to the form.
/// Resolves to true when the server saved a product (the caller then reloads).
///
/// This only decides where to go; whether the user may add is checked by the server.
Future<bool> openAddProduct(BuildContext context, WidgetRef ref, AddProductTarget target) async {
  if (!ref.read(authControllerProvider).isSignedIn) {
    await context.push<void>(Routes.signIn);
    if (!context.mounted || !ref.read(authControllerProvider).isSignedIn) {
      return false; // the user left the sign-in without signing in
    }
  }

  final saved = await context.push<bool>(Routes.addProduct(target.storeId), extra: target);
  return saved ?? false;
}

/// The "Pridėti produktą" button. Disabled with a short reason when there is
/// no connection to the server.
class AddProductButton extends StatelessWidget {
  const AddProductButton({super.key, required this.onPressed, this.offline = false});

  final VoidCallback onPressed;

  /// The screen is showing saved data because the server cannot be reached.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: offline ? null : onPressed,
          icon: const Icon(Icons.add),
          label: const Text('Pridėti produktą'),
        ),
        if (offline)
          Text(
            'Be ryšio produktų pridėti negalima',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
