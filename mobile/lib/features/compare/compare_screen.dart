import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import '../history/open_history.dart';
import '../submit_price/open_submit_price.dart';
import '../submit_price/submit_price_models.dart';
import 'compare_controller.dart';
import 'compare_models.dart';

/// What the price is: shown on the comparison so nobody expects a deposit in it.
const String priceExplanation = 'Kaina – vienos pakuotės kaina be užstato';

const String noPricesMessage = 'Šiam produktui kainų kol kas nėra';
const String singleStoreMessage = 'Palyginimui trūksta kitų parduotuvių duomenų';
const String staleMessage = 'Neatnaujinta daugiau nei 7 dienas';
const String cheapestLabel = 'Pigiausia';

/// The same product's prices in different stores. Guests may open it.
class ProductCompareScreen extends ConsumerWidget {
  const ProductCompareScreen({
    super.key,
    required this.productId,
    this.productName,
    this.volumeMl,
  });

  final int productId;

  /// Shown in the header until the server answers.
  final String? productName;
  final int? volumeMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = compareControllerProvider(productId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final view = state.view;

    final comparison = view is ViewSuccess<ProductComparison> ? view.data : null;
    final loaded = comparison?.product;
    final name = loaded?.name ?? productName;
    final volume = loaded?.volumeMl ?? volumeMl;

    // With fewer than two prices there is nothing to put in order.
    final showSort = comparison == null || comparison.offers.length >= 2;

    return AppScaffold(
      title: 'Kainų palyginimas',
      body: AgeGuard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(name: name, volumeMl: volume, brand: loaded?.brand),
            if (showSort) _SortChoice(selected: state.sort, onSelected: controller.setSort),
            const Divider(height: 1),
            Expanded(
              child: AsyncStateView<ProductComparison>(
                state: view,
                onRetry: controller.load,
                builder: (context, comparison) => comparison.offers.isEmpty
                    ? const _NoPrices()
                    : _OfferList(
                        comparison: comparison,
                        onSubmitPrice: (offer) async {
                          final saved = await openSubmitPrice(
                            context,
                            ref,
                            SubmitPriceTarget(
                              productId: comparison.product.id,
                              productName: comparison.product.name,
                              volumeMl: comparison.product.volumeMl,
                              storeId: offer.storeId,
                              storeName: offer.storeName,
                              currentPriceCents: offer.priceCents,
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
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.volumeMl, required this.brand});

  final String? name;
  final int? volumeMl;
  final String? brand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (volumeMl != null) '$volumeMl ml',
      ?brand,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null) Text(name!, style: theme.textTheme.titleLarge),
          if (details.isNotEmpty) Text(details, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(priceExplanation, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// "Pigiausia pirmiausia" / "Brangiausia pirmiausia". The selected one also
/// shows a check mark, so the choice is not told by colour alone.
class _SortChoice extends StatelessWidget {
  const _SortChoice({required this.selected, required this.onSelected});

  final PriceSort selected;
  final ValueChanged<PriceSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: const Text('Pigiausia pirmiausia'),
            selected: selected == PriceSort.asc,
            showCheckmark: true,
            onSelected: (_) => onSelected(PriceSort.asc),
          ),
          ChoiceChip(
            label: const Text('Brangiausia pirmiausia'),
            selected: selected == PriceSort.desc,
            showCheckmark: true,
            onSelected: (_) => onSelected(PriceSort.desc),
          ),
        ],
      ),
    );
  }
}

/// The product exists but no store has a confirmed price for it.
class _NoPrices extends StatelessWidget {
  const _NoPrices();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(noPricesMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferList extends StatelessWidget {
  const _OfferList({required this.comparison, required this.onSubmitPrice});

  final ProductComparison comparison;
  final void Function(StoreOffer offer) onSubmitPrice;

  @override
  Widget build(BuildContext context) {
    final offers = comparison.offers;
    final cheapest = cheapestPriceCents(offers)!;
    final dearest = offers.map((o) => o.priceCents).reduce((a, b) => a > b ? a : b);

    // "Pigiausia" only means something when some store is dearer; if every
    // price is the same, or there is just one, labelling it would be noise.
    final markCheapest = offers.length >= 2 && cheapest < dearest;

    return ListView(
      children: [
        if (comparison.singleStore) const _SingleStoreNotice(),
        for (final offer in offers) ...[
          _OfferRow(
            offer: offer,
            extraCents: differenceFromCheapestCents(offer, cheapest),
            isCheapest: markCheapest && offer.priceCents == cheapest,
            // The price history of this product (id + volume) in this store.
            onTap: () => openHistory(
              context,
              productId: comparison.product.id,
              storeId: offer.storeId,
              productName: comparison.product.name,
              volumeMl: comparison.product.volumeMl,
              storeName: offer.storeName,
            ),
            onSubmit: () => onSubmitPrice(offer),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

/// Only one store has a price: it is shown, with a note why nothing is compared.
class _SingleStoreNotice extends StatelessWidget {
  const _SingleStoreNotice();

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(singleStoreMessage, style: TextStyle(color: scheme.onSecondaryContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.offer,
    required this.extraCents,
    required this.isCheapest,
    required this.onTap,
    required this.onSubmit,
  });

  final StoreOffer offer;

  /// Opens "Atnaujinti kainą" for this product in this store.
  final VoidCallback onSubmit;

  /// Opens this store's price history of the product.
  final VoidCallback onTap;

  /// How much dearer than the cheapest offer, in cents.
  final int extraCents;

  /// Marked with the word "Pigiausia" (and an icon), never by colour alone.
  final bool isCheapest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The whole row is the tap target (much taller than 48 dp).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
    MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.storeName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(offer.storeAddress, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Patikrinta: ${formatDateTime(offer.observedAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (offer.isStale) ...[
                    const SizedBox(height: 4),
                    // A text and an icon, not a colour, tells the price is old.
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            staleMessage,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPrice(offer.priceCents), style: theme.textTheme.titleLarge),
                if (isCheapest)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        cheapestLabel,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  )
                else if (extraCents > 0)
                  Text(
                    '${formatPriceDifference(extraCents)} brangiau',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
      ),
    ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: SubmitPriceButton(onPressed: onSubmit),
        ),
      ],
    );
  }
}
