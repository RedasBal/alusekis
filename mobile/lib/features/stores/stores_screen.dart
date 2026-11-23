import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import '../settings/settings_controller.dart';
import 'location_service.dart';
import 'map_provider.dart';
import 'store_models.dart';
import 'store_repository.dart';
import 'stores_controller.dart';

class StoresScreen extends StatelessWidget {
  const StoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'Parduotuvės',
      body: AgeGuard(child: _StoresBody()),
    );
  }
}

class _StoresBody extends ConsumerWidget {
  const _StoresBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storesControllerProvider);
    final controller = ref.read(storesControllerProvider.notifier);
    final inLocationMode = state.mode == StoreSearchMode.location;

    return Column(
      children: [
        const _Controls(),
        const Divider(height: 1),
        Expanded(
          child: AsyncStateView<List<StoreItem>>(
            state: state.result,
            onRetry: controller.reload,
            emptyMessage: inLocationMode
                ? 'Parduotuvių šiame spindulyje nerasta.'
                : 'Parduotuvių šiame mieste nerasta.',
            builder: (context, stores) => state.showMap
                ? ref.watch(mapProviderProvider).build(
                      context,
                      stores: stores,
                      origin: state.origin,
                      onStoreTap: (store) => showStoreSheet(context, store),
                    )
                : _StoreList(stores: stores),
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storesControllerProvider);
    final controller = ref.read(storesControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final settingsController = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    // Server list when available, the built-in list while loading or offline.
    final cityNames = ref.watch(citiesProvider).asData?.value.map((c) => c.name).toList() ??
        availableCities;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownMenu<String>(
            label: const Text('Miestas'),
            expandedInsets: EdgeInsets.zero,
            initialSelection: settings.city,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              for (final name in cityNames) DropdownMenuEntry(value: name, label: name),
            ],
            onSelected: (name) {
              if (name != null) {
                controller.selectCity(name);
              }
            },
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: state.locating ? null : controller.useMyLocation,
            icon: state.locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(state.locating ? 'Nustatoma vieta…' : 'Naudoti vietą'),
          ),
          if (state.locationProblem != null) ...[
            const SizedBox(height: 8),
            _LocationNotice(problem: state.locationProblem!),
          ],
          if (state.mode == StoreSearchMode.location) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.near_me_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pagal jūsų vietą · spindulys ${settings.radiusKm} km',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Slider(
              value: settings.radiusKm.toDouble(),
              min: minRadiusKm.toDouble(),
              max: maxRadiusKm.toDouble(),
              divisions: maxRadiusKm - minRadiusKm,
              label: '${settings.radiusKm} km',
              semanticFormatterCallback: (value) => '${value.round()} km',
              onChanged: (value) => settingsController.setRadiusKm(value.round()),
              onChangeEnd: (_) => controller.reload(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.selectCity(settings.city),
                icon: const Icon(Icons.location_city),
                label: Text('Rodyti visą miestą: ${settings.city}'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(minTapTarget, minTapTarget),
            ),
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.map_outlined),
                label: Text('Žemėlapis'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.list),
                label: Text('Sąrašas'),
              ),
            ],
            selected: {state.showMap},
            onSelectionChanged: (selection) => controller.setShowMap(selection.single),
          ),
        ],
      ),
    );
  }
}

/// Explains why the location could not be used and what still works.
class _LocationNotice extends ConsumerWidget {
  const _LocationNotice({required this.problem});

  final LocationFailure problem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = switch (problem) {
      LocationFailure.denied =>
        'Vietos leidimas neduotas. Pasirinkite miestą arba bandykite dar kartą.',
      LocationFailure.deniedForever =>
        'Vietos leidimas išjungtas. Pasirinkite miestą arba įjunkite leidimą '
            'telefono nustatymuose.',
      LocationFailure.serviceDisabled =>
        'Vietos nustatymas telefone išjungtas. Pasirinkite miestą.',
      LocationFailure.unavailable =>
        'Nepavyko nustatyti vietos. Pasirinkite miestą arba bandykite vėliau.',
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer)),
                ),
              ],
            ),
            if (problem == LocationFailure.deniedForever)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: ref.read(storesControllerProvider.notifier).openAppSettings,
                  child: const Text('Atidaryti nustatymus'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoreList extends StatelessWidget {
  const _StoreList({required this.stores});

  final List<StoreItem> stores;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: stores.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final store = stores[index];
        final distance = store.distanceKm;
        return ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.storefront_outlined),
          title: Text(store.name),
          subtitle: Text(store.address),
          trailing: distance == null ? null : Text(formatDistance(distance)),
          onTap: () => showStoreSheet(context, store),
        );
      },
    );
  }
}

/// Name and address of the tapped store (from a map marker or the list).
Future<void> showStoreSheet(BuildContext context, StoreItem store) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final distance = store.distanceKm;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(store.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${store.address}, ${store.cityName}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              if (distance != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.near_me_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'Atstumas: ${formatDistance(distance)}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Uždaryti'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
