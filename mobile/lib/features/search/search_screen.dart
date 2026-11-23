import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/placeholder_body.dart';
import '../age_gate/age_gate_host.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Paieška',
      onBack: () => context.go(Routes.stores),
      body: const AgeGuard(
        child: PlaceholderBody(
          icon: Icons.search,
          text: 'Produktų paieška bus čia.',
        ),
      ),
    );
  }
}
