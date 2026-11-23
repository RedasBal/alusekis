import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_models.dart';
import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../auth/delete_account_dialog.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    return AppScaffold(
      title: 'Paskyra',
      onBack: () => context.go(Routes.stores),
      body: ListView(
        children: [
          if (auth.status == AuthStatus.loading)
            const LinearProgressIndicator(),
          if (user != null)
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(user.email),
              subtitle: const Text('Prisijungta'),
            ),
          if (auth.status == AuthStatus.signedOut) ...[
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.login),
              title: const Text('Prisijungti'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.login),
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.person_add_alt_outlined),
              title: const Text('Registruotis'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.register),
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.lock_reset),
              title: const Text('Atkurti slaptažodį'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.forgotPassword),
            ),
          ],
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Nustatymai'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.settings),
          ),
          if (user != null) ...[
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.logout),
              title: const Text('Atsijungti'),
              onTap: () => _logout(context, ref),
            ),
            ListTile(
              minTileHeight: 56,
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Ištrinti paskyrą',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _delete(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Atsijungta.')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await showDeleteAccountDialog(context);
    if (deleted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Paskyra ištrinta.')),
      );
    }
  }
}
