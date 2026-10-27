import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';
import '../explore/trade_sheet.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const TopBar(),
      body: AsyncBody(
        value: ref.watch(portfolioProvider),
        onRetry: () => ref.invalidate(portfolioProvider),
        builder: (portfolio) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(portfolioProvider);
            await ref.read(portfolioProvider.future);
          },
          child: _PortfolioContent(portfolio: portfolio),
        ),
      ),
    );
  }
}

class _PortfolioContent extends ConsumerWidget {
  const _PortfolioContent({required this.portfolio});

  final Portfolio portfolio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.totalValue, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: FittedBox(
                                child: Text(formatEur(portfolio.totalValue, locale: locale),
                                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filled(
                              style: IconButton.styleFrom(backgroundColor: AppColors.pink),
                              onPressed: () => context.go('/explore'),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${l.cash}: ${formatEur(portfolio.cash, locale: locale, decimals: 0)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('${l.stocks}: ${formatEur(portfolio.holdingsValue, locale: locale, decimals: 0)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(height: 200, child: _ValueChart(portfolio: portfolio)),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: Text(l.myStocks, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            Text(l.holdings(portfolio.positions.length), style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 12),
        if (portfolio.positions.isEmpty)
          SectionCard(
            child: Column(
              children: [
                Text(l.noHoldings, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.go('/explore'), child: Text(l.exploreStocks)),
              ],
            ),
          )
        else
          for (final p in portfolio.positions) _PositionTile(position: p),
        if (portfolio.recentTrades.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(l.recentActivity, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final t in portfolio.recentTrades.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                t.side == 'buy' ? Icons.add_circle_outline : Icons.remove_circle_outline,
                color: t.side == 'buy' ? AppColors.green : AppColors.red,
              ),
              title: Text('${t.side == 'buy' ? l.bought : l.sold} ${t.symbol}'),
              subtitle: Text(
                '${l.sharesCount(formatQuantity(t.quantity, locale: locale))} · ${DateFormat.yMMMd(locale).add_Hm().format(t.executedAt)}',
              ),
              trailing: Text(formatEur(t.amountEur, locale: locale), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ],
    );
  }
}

class _ValueChart extends StatelessWidget {
  const _ValueChart({required this.portfolio});

  final Portfolio portfolio;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Daily snapshots plus today's live value as the last point.
    final today = DateUtils.dateOnly(DateTime.now());
    final points = [
      ...portfolio.history.where((h) => h.day.isBefore(today)),
      HistoryPoint(today, portfolio.totalValue),
    ];
    final spots = [for (final (i, p) in points.indexed) FlSpot(i.toDouble(), p.value)];
    final values = points.map((p) => p.value);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    // At least ±5% of the value, so a flat or single-point history still gets distinct
    // axis labels.
    final pad = [(maxY - minY) * 0.15, maxY.abs() * 0.05, 1.0].reduce((a, b) => a > b ? a : b);
    final rising = points.length < 2 || points.last.value >= points.first.value;
    final color = rising ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 12, 16, 4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY + 2 * pad) / 2,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: (maxY - minY + 2 * pad) / 2,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(formatEur(value, locale: locale, decimals: 0), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${DateFormat.MMMd(locale).format(points[s.x.toInt()].day)}\n${formatEur(s.y, locale: locale)}',
                    const TextStyle(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: spots.length < 12),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionTile extends ConsumerWidget {
  const _PositionTile({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final p = position;
    final gain = p.pnl >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final instruments = await ref.read(instrumentsProvider.future);
            final instrument = instruments.where((i) => i.symbol == p.symbol).firstOrNull;
            if (instrument != null && context.mounted) showTradeSheet(context, instrument);
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                InstrumentAvatar(symbol: p.symbol, logoUrl: p.logoUrl, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(p.symbol, style: const TextStyle(color: AppColors.textSecondary)),
                      Text(l.sharesCount(formatQuantity(p.quantity, locale: locale)), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatEur(p.valueEur, locale: locale), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(
                      '${gain ? '+' : ''}${formatEur(p.pnl, locale: locale)} (${formatPercent(p.pnlPct, locale: locale)})',
                      style: TextStyle(color: gain ? AppColors.green : AppColors.red, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
