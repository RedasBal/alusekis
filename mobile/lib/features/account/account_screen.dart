import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Paskyra',
      onBack: () => context.go(Routes.stores),
      body: ListView(
        children: [
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Nustatymai'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.settings),
          ),
        ],
      ),
    );
  }
}
