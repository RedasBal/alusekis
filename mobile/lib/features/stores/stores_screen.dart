import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/placeholder_body.dart';
import '../age_gate/age_gate_host.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Parduotuvės',
      body: AgeGuard(
        child: PlaceholderBody(
          icon: Icons.storefront_outlined,
          text: 'Parduotuvių sąrašas bus čia.',
        ),
      ),
    );
  }
}
