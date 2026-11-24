import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';

/// What is already known about a product when its comparison is opened, so the
/// header can show it before the server answers.
class ProductHint {
  const ProductHint({required this.name, required this.volumeMl});

  final String name;
  final int volumeMl;
}

/// Opens the price comparison of one product (id + volume identify it).
/// Used by the search results and the store price list.
void openComparison(
  BuildContext context, {
  required int productId,
  required String name,
  required int volumeMl,
}) {
  context.push(
    Routes.productPrices(productId),
    extra: ProductHint(name: name, volumeMl: volumeMl),
  );
}
