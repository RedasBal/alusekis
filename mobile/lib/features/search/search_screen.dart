import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import 'product_models.dart';
import 'product_search_controller.dart';
import 'search_query.dart';

/// "Paieška": find a product by (part of) its name. Guests may use it.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(productSearchControllerProvider).text);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    ref.read(productSearchControllerProvider.notifier).onTextChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productSearchControllerProvider);
    final controller = ref.read(productSearchControllerProvider.notifier);
    final view = state.view;

    return AppScaffold(
      title: 'Paieška',
      onBack: () => context.go(Routes.stores),
      body: AgeGuard(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _text,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                maxLength: maxSearchLength,
                inputFormatters: [LengthLimitingTextInputFormatter(maxSearchLength)],
                // The 100 limit is enforced silently; a counter would only add noise.
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                    null,
                onChanged: controller.onTextChanged,
                decoration: InputDecoration(
                  labelText: 'Ieškoti produkto',
                  hintText: 'Pavyzdžiui, Švyturys',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: state.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Išvalyti',
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                ),
              ),
            ),
            Expanded(
              child: view == null
                  ? const _Hint()
                  : AsyncStateView<List<ProductSearchItem>>(
                      state: view,
                      onRetry: controller.retry,
                      emptyMessage: 'Nieko nerasta. Pakeiskite užklausą.',
                      builder: (context, items) => _Results(items: items),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the text is too short to search.
class _Hint extends StatelessWidget {
  const _Hint();

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
              Icon(Icons.search, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(searchHint, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.items});

  final List<ProductSearchItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _ResultTile(item: items[index]),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.item});

  final ProductSearchItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = item.lowestPrice;
    final brand = item.brand;

    return ListTile(
      minTileHeight: 64,
      title: Text(item.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(brand == null ? '${item.volumeMl} ml' : '${item.volumeMl} ml · $brand'),
          if (price != null && price.isStale)
            // A text and an icon, not a colour, tells the price is old.
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Neatnaujinta daugiau nei 7 dienas',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
        ],
      ),
      trailing: price == null
          ? Text('Kainų kol kas nėra', style: theme.textTheme.bodySmall)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPrice(price.priceCents), style: theme.textTheme.titleMedium),
                Text(price.storeName, style: theme.textTheme.bodySmall),
              ],
            ),
      // Comparing prices and history come in later tasks; for now just the name.
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(item.name))),
    );
  }
}
