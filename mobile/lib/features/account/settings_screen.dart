import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../settings/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Nustatymai',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Tema', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(minTapTarget, minTapTarget),
            ),
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Sistemos')),
              ButtonSegment(value: ThemeMode.light, label: Text('Šviesi')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Tamsi')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) =>
                controller.setThemeMode(selection.single),
          ),
          const SizedBox(height: 24),
          Text('Miestas', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownMenu<String>(
            expandedInsets: EdgeInsets.zero,
            initialSelection: settings.city,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              for (final city in availableCities)
                DropdownMenuEntry(value: city, label: city),
            ],
            onSelected: (city) {
              if (city != null) {
                controller.setCity(city);
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Paieškos spindulys: ${settings.radiusKm} km',
            style: theme.textTheme.titleMedium,
          ),
          Slider(
            value: settings.radiusKm.toDouble(),
            min: minRadiusKm.toDouble(),
            max: maxRadiusKm.toDouble(),
            divisions: maxRadiusKm - minRadiusKm,
            label: '${settings.radiusKm} km',
            semanticFormatterCallback: (value) => '${value.round()} km',
            onChanged: (value) => controller.setRadiusKm(value.round()),
          ),
        ],
      ),
    );
  }
}
