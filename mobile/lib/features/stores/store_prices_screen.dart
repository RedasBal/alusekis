import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import '../compare/open_comparison.dart';
import 'store_prices_controller.dart';
import 'store_prices_models.dart';

/// Products and prices of one store. Guests may open it.
class StorePricesScreen extends ConsumerWidget {
  const StorePricesScreen({super.key, required this.storeId, this.storeName});

  final int storeId;

  /// Shown in the title until the server answers.
  final String? storeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = storePricesControllerProvider(storeId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final view = state.view;
    final title = (view is ViewSuccess<StorePricesData> ? view.data.store.name : storeName) ??
        'Kainos';

    return AppScaffold(
      title: title,
      body: AgeGuard(
        child: AsyncStateView<StorePricesData>(
          state: view,
          onRetry: controller.load,
          builder: (context, data) => _PricesList(
            data: data,
            loadingMore: state.loadingMore,
            moreError: state.moreError,
            onRetry: controller.load,
            onLoadMore: controller.loadMore,
          ),
        ),
      ),
    );
  }
}

class _PricesList extends StatelessWidget {
  const _PricesList({
    required this.data,
    required this.loadingMore,
    required this.moreError,
    required this.onRetry,
    required this.onLoadMore,
  });

  final StorePricesData data;
  final bool loadingMore;
  final String? moreError;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final cachedAt = data.cachedAt;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (cachedAt != null)
          _CachedNotice(syncedAt: cachedAt, onRetry: onRetry),
        if (data.items.isEmpty)
          const _EmptyPrices()
        else
          for (final price in data.items) _PriceRow(price: price),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (moreError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(width: 12),
                  Expanded(child: Text(moreError!)),
                ],
              ),
            ),
          ),
        if (data.hasMore && !loadingMore)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton(
              onPressed: onLoadMore,
              child: Text(moreError == null ? 'Rodyti daugiau' : 'Bandyti dar kartą'),
            ),
          ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.price});

  final StorePrice price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Column(
        children: [
          // The whole row is the tap target (taller than 48 dp): it opens the
          // comparison of this product (id + volume) across stores.
          InkWell(
            onTap: () => openComparison(
              context,
              productId: price.productId,
              name: price.productName,
              volumeMl: price.volumeMl,
            ),
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(price.productName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('${price.volumeMl} ml', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Patikrinta: ${formatDateTime(price.observedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (price.isStale) ...[
                        const SizedBox(height: 4),
                        // A text and an icon, not a colour, tells the price is old.
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 16, color: theme.colorScheme.error),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Neatnaujinta daugiau nei 7 dienas',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatPrice(price.priceCents), style: theme.textTheme.titleLarge),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _CachedNotice extends StatelessWidget {
  const _CachedNotice({required this.syncedAt, required this.onRetry});

  final DateTime syncedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(16),
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
                Icon(Icons.cloud_off_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rodomi išsaugoti duomenys (sinchronizuota ${formatDateTime(syncedAt)})',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onRetry, child: const Text('Bandyti dar kartą')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPrices extends StatelessWidget {
  const _EmptyPrices();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Semantics(
        liveRegion: true,
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Šioje parduotuvėje kainų kol kas nėra',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
