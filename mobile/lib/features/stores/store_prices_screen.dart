import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../add_product/add_product_models.dart';
import '../add_product/open_add_product.dart';
import '../age_gate/age_gate_host.dart';
import '../compare/open_comparison.dart';
import '../report/open_report.dart';
import '../report/report_models.dart';
import '../submit_price/open_submit_price.dart';
import '../submit_price/submit_price_models.dart';
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
            onReportPrice: (price) => openReport(
              context,
              ref,
              ReportTarget(
                priceEntryId: price.priceEntryId,
                productName: price.productName,
                volumeMl: price.volumeMl,
                storeName: data.store.name,
                priceCents: price.priceCents,
                observedAt: price.observedAt,
              ),
            ),
            onAddProduct: () async {
              final added = await openAddProduct(
                context,
                ref,
                AddProductTarget(storeId: data.store.id, storeName: data.store.name),
              );
              // Back from a saved product: load again so it shows with its price.
              if (added) {
                controller.load();
              }
            },
            onSubmitPrice: (price) async {
              final saved = await openSubmitPrice(
                context,
                ref,
                SubmitPriceTarget(
                  productId: price.productId,
                  productName: price.productName,
                  volumeMl: price.volumeMl,
                  storeId: data.store.id,
                  storeName: data.store.name,
                  currentPriceCents: price.priceCents,
                ),
              );
              // Back from a saved price: load again so the new price shows.
              if (saved) {
                controller.load();
              }
            },
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
    required this.onReportPrice,
    required this.onAddProduct,
    required this.onSubmitPrice,
  });

  final StorePricesData data;
  final bool loadingMore;
  final String? moreError;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final void Function(StorePrice price) onReportPrice;
  final VoidCallback onAddProduct;
  final void Function(StorePrice price) onSubmitPrice;

  @override
  Widget build(BuildContext context) {
    final cachedAt = data.cachedAt;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (cachedAt != null)
          _CachedNotice(syncedAt: cachedAt, onRetry: onRetry),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            // Saved data means the server cannot be reached (FR-16).
            child: AddProductButton(onPressed: onAddProduct, offline: data.isFromCache),
          ),
        ),
        if (data.items.isEmpty)
          const _EmptyPrices()
        else
          for (final price in data.items)
            _PriceRow(
              price: price,
              // Saved data means the server cannot be reached (FR-16).
              offline: data.isFromCache,
              onSubmit: () => onSubmitPrice(price),
              onReport: () => onReportPrice(price),
            ),
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
  const _PriceRow({
    required this.price,
    required this.offline,
    required this.onSubmit,
    required this.onReport,
  });

  final StorePrice price;
  final bool offline;
  final VoidCallback onSubmit;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          // The whole row is the tap target (taller than 48 dp): it opens the
          // comparison of this product (id + volume) across stores.
          child: InkWell(
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SubmitPriceButton(onPressed: onSubmit, offline: offline),
              ReportButton(onPressed: onReport, offline: offline),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
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
