import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';

/// What is already known when a history is opened, so the header can show it
/// before the server answers.
class HistoryHint {
  const HistoryHint({required this.productName, required this.volumeMl, required this.storeName});

  final String productName;
  final int volumeMl;
  final String storeName;
}

/// Opens the price history of one product (id + volume) in one store.
/// Used by the price comparison, where each store row leads here.
void openHistory(
  BuildContext context, {
  required int productId,
  required int storeId,
  required String productName,
  required int volumeMl,
  required String storeName,
}) {
  context.push(
    Routes.priceHistory(productId, storeId),
    extra: HistoryHint(productName: productName, volumeMl: volumeMl, storeName: storeName),
  );
}
