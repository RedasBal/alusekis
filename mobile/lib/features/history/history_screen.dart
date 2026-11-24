import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/async_state_view.dart';
import '../age_gate/age_gate_host.dart';
import 'chart_points.dart';
import 'history_controller.dart';
import 'history_models.dart';

/// The recorded prices of one product in one store, as a chart and a list.
/// Guests may open it.
class PriceHistoryScreen extends ConsumerWidget {
  const PriceHistoryScreen({
    super.key,
    required this.productId,
    required this.storeId,
    this.productName,
    this.volumeMl,
    this.storeName,
  });

  final int productId;
  final int storeId;

  /// Shown in the header until the server answers.
  final String? productName;
  final int? volumeMl;
  final String? storeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = historyControllerProvider((productId, storeId));
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final view = state.view;

    final history = view is ViewSuccess<PriceHistory> ? view.data : null;

    return AppScaffold(
      title: 'Kainų istorija',
      body: AgeGuard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              productName: history?.product.name ?? productName,
              volumeMl: history?.product.volumeMl ?? volumeMl,
              storeName: history?.store.name ?? storeName,
              storeAddress: history?.store.address,
            ),
            _PeriodChoice(selected: state.period, onSelected: controller.setPeriod),
            const Divider(height: 1),
            Expanded(
              child: AsyncStateView<PriceHistory>(
                state: view,
                onRetry: controller.load,
                builder: (context, history) => _HistoryBody(
                  history: history,
                  period: state.period,
                  onShowLonger: controller.setPeriod,
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
  const _Header({
    required this.productName,
    required this.volumeMl,
    required this.storeName,
    required this.storeAddress,
  });

  final String? productName;
  final int? volumeMl;
  final String? storeName;
  final String? storeAddress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = [?storeName, ?storeAddress].join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (productName != null) Text(productName!, style: theme.textTheme.titleLarge),
          if (volumeMl != null) Text('$volumeMl ml', style: theme.textTheme.bodyLarge),
          if (store.isNotEmpty) Text(store, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// "7 d. / 30 d. / 90 d.". The selected segment also shows a check mark, so
/// the choice is not told by colour alone.
class _PeriodChoice extends StatelessWidget {
  const _PeriodChoice({required this.selected, required this.onSelected});

  final HistoryPeriod selected;
  final ValueChanged<HistoryPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<HistoryPeriod>(
        style: SegmentedButton.styleFrom(minimumSize: const Size(minTapTarget, minTapTarget)),
        segments: [
          for (final period in HistoryPeriod.values)
            ButtonSegment(value: period, label: Text(period.label)),
        ],
        selected: {selected},
        onSelectionChanged: (selection) => onSelected(selection.single),
      ),
    );
  }
}

/// Shown when there is no recorded price in the chosen period.
const String emptyHistoryMessage = 'Per pasirinktą laikotarpį kainų įrašų nėra';

/// Shown when the period holds exactly one recorded price.
const String singleEntryMessage = 'Užregistruotas vienas kainos įrašas';

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.history,
    required this.period,
    required this.onShowLonger,
  });

  final PriceHistory history;
  final HistoryPeriod period;
  final ValueChanged<HistoryPeriod> onShowLonger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (history.points.isEmpty) {
      return _EmptyHistory(longer: period.longer, onShowLonger: onShowLonger);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (history.points.length == 1) const _SingleEntryNotice(),
        _PriceChart(history: history),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Užregistruoti kainų įrašai', style: theme.textTheme.titleMedium),
        ),
        for (final point in history.points) ...[
          _PointRow(point: point),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

/// No recorded price in the period: says so and, unless this is already the
/// longest period, offers the next longer one.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.longer, required this.onShowLonger});

  final HistoryPeriod? longer;
  final ValueChanged<HistoryPeriod> onShowLonger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final longer = this.longer;

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
              Text(
                emptyHistoryMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              if (longer != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => onShowLonger(longer),
                  child: Text('Rodyti ilgesnį laikotarpį (${longer.label})'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One recorded price: it is a single point on the chart, and says so.
class _SingleEntryNotice extends StatelessWidget {
  const _SingleEntryNotice();

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
          children: [
            Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                singleEntryMessage,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Points at the recorded prices, joined by straight lines between neighbouring
/// recorded points only: no smoothing, no values in between.
class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.history});

  final PriceHistory history;

  static String _dateLabel(double millis) => formatDateTime(
        DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true),
      ).replaceFirst(' ', '\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall;

    final chartPoints = buildChartPoints(history.points);
    final bounds = chartBoundsFor(history, chartPoints);
    final first = history.points.first;
    final last = history.points.last;

    return Semantics(
      label: 'Kainų grafikas: ${history.points.length} įrašų, '
          'nuo ${formatDateTime(first.observedAt)} iki ${formatDateTime(last.observedAt)}. '
          'Visi įrašai išvardyti žemiau.',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 32, 8),
            child: LineChart(
              LineChartData(
                minX: bounds.minX,
                maxX: bounds.maxX,
                minY: bounds.minY,
                maxY: bounds.maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (final p in chartPoints) FlSpot(p.x, p.y)],
                    isCurved: false, // straight lines between real points, nothing in between
                    barWidth: 2,
                    color: scheme.primary,
                    dotData: const FlDotData(show: true), // every recorded price is a visible dot
                  ),
                ],
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true, border: Border.all(color: scheme.outline)),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 64,
                      interval: yAxisIntervalCents(bounds),
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(formatPrice(value.round()), style: labelStyle),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      // One label at each end of the window.
                      interval: bounds.maxX - bounds.minX,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _dateLabel(value),
                          textAlign: TextAlign.center,
                          style: labelStyle,
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${formatPrice(spot.y.round())}\n'
                          '${formatDateTime(DateTime.fromMillisecondsSinceEpoch(spot.x.round(), isUtc: true))}',
                          TextStyle(color: scheme.onInverseSurface),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});

  final PricePoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(formatDateTime(point.observedAt), style: theme.textTheme.bodyLarge),
              ),
              Text(formatPrice(point.priceCents), style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
