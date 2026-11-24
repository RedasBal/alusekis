import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import 'compare_controller.dart';
import 'compare_models.dart';

/// What the price is: shown on the comparison so nobody expects a deposit in it.
const String priceExplanation = 'Kaina – vienos pakuotės kaina be užstato';

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

    final loaded = view is ViewSuccess<ProductComparison> ? view.data.product : null;
    final name = loaded?.name ?? productName;
    final volume = loaded?.volumeMl ?? volumeMl;

    return AppScaffold(
      title: 'Kainų palyginimas',
      body: AgeGuard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(name: name, volumeMl: volume, brand: loaded?.brand),
            _SortChoice(selected: state.sort, onSelected: controller.setSort),
            const Divider(height: 1),
            Expanded(
              child: AsyncStateView<ProductComparison>(
                state: view,
                onRetry: controller.load,
                builder: (context, comparison) => _OfferList(comparison: comparison),
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

class _OfferList extends StatelessWidget {
  const _OfferList({required this.comparison});

  final ProductComparison comparison;

  @override
  Widget build(BuildContext context) {
    final offers = comparison.offers;
    final cheapest = cheapestPriceCents(offers);

    return ListView.separated(
      itemCount: offers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final offer = offers[index];
        return _OfferRow(
          offer: offer,
          extraCents: cheapest == null ? 0 : differenceFromCheapestCents(offer, cheapest),
        );
      },
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer, required this.extraCents});

  final StoreOffer offer;

  /// How much dearer than the cheapest offer, in cents.
  final int extraCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
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
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPrice(offer.priceCents), style: theme.textTheme.titleLarge),
                if (extraCents > 0)
                  Text(
                    '${formatPriceDifference(extraCents)} brangiau',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
