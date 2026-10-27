import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';
import 'trade_sheet.dart';

const _sectors = ['technology', 'finance', 'healthcare', 'consumer', 'energy', 'industrials', 'etf'];

String sectorLabel(AppLocalizations l, String sector) => switch (sector) {
      'technology' => l.sectorTechnology,
      'finance' => l.sectorFinance,
      'healthcare' => l.sectorHealthcare,
      'consumer' => l.sectorConsumer,
      'energy' => l.sectorEnergy,
      'industrials' => l.sectorIndustrials,
      'etf' => l.sectorEtf,
      _ => sector,
    };

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String? _sector;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quotes = ref.watch(quotesProvider).value ?? const <String, Quote>{};
    return Scaffold(
      appBar: const TopBar(),
      body: AsyncBody(
        value: ref.watch(instrumentsProvider),
        onRetry: () => ref.invalidate(instrumentsProvider),
        builder: (instruments) {
          final q = _query.toLowerCase();
          final visible = instruments
              .where((i) => _sector == null || i.sector == _sector)
              .where((i) => q.isEmpty || i.name.toLowerCase().contains(q) || i.symbol.toLowerCase().contains(q))
              .toList();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF2A1E2E), AppColors.background], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${l.exploreTitle} 📈', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(l.exploreSubtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 17)),
                      const SizedBox(height: 20),
                      TextField(
                        decoration: InputDecoration(hintText: l.searchHint, prefixIcon: const Icon(Icons.search, color: AppColors.pink)),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final sector in [null, ..._sectors])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(sector == null ? l.allSectors : sectorLabel(l, sector)),
                            selected: _sector == sector,
                            selectedColor: AppColors.pink,
                            onSelected: (_) => setState(() => _sector = sector),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(l.pricesNotice, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(l.noResults)))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.05,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _InstrumentCard(instrument: visible[i], quote: quotes[visible[i].symbol]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({required this.instrument, required this.quote});

  final Instrument instrument;
  final Quote? quote;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final change = quote?.changePct;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showTradeSheet(context, instrument),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InstrumentAvatar(symbol: instrument.symbol, logoUrl: instrument.logoUrl, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(instrument.symbol, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        Text(instrument.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(l.currentPrice, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                quote == null ? '—' : formatPrice(quote!.price, instrument.currency, locale: locale),
                style: const TextStyle(color: AppColors.pink, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              if (change != null)
                Text(
                  formatPercent(change, locale: locale),
                  style: TextStyle(color: change >= 0 ? AppColors.green : AppColors.red, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
