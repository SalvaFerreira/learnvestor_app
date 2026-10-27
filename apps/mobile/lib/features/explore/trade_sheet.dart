import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

Future<void> showTradeSheet(BuildContext context, Instrument instrument) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TradeSheet(instrument: instrument),
    );

/// Buy by euro amount, sell by amount or everything. The price shown is indicative:
/// the server executes at its own cached quote.
class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet({super.key, required this.instrument});

  final Instrument instrument;

  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  final _amount = TextEditingController();
  bool _buy = true;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;

  void _setAmount(double value) {
    _amount.text = value.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _submit({Position? sellAll}) async {
    final l = context.l10n;
    final symbol = widget.instrument.symbol;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).placeTrade(
            symbol: symbol,
            buy: _buy,
            amountEur: sellAll == null ? _amountValue : null,
            quantity: sellAll?.quantity,
          );
      refreshAfterTrade(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, _buy ? l.tradeBought(symbol) : l.tradeSold(symbol));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final instrument = widget.instrument;
    final quote = ref.watch(quotesProvider).value?[instrument.symbol];
    final fx = ref.watch(fxRatesProvider).value?[instrument.currency];
    final player = ref.watch(playerStateProvider).value;
    final position = ref.watch(portfolioProvider).value?.positionFor(instrument.symbol);
    final priceEur = quote != null && fx != null ? quote.price / fx : null;
    final cash = player?.cash ?? 0;
    final amount = _amountValue;
    final limit = _buy ? cash : (position?.valueEur ?? 0);
    final valid = priceEur != null && amount >= (player?.economy.minTradeEur ?? 1) && amount <= limit + 0.005;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InstrumentAvatar(symbol: instrument.symbol, logoUrl: instrument.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(instrument.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${instrument.symbol} · ${instrument.exchange}', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    quote == null ? '—' : formatPrice(quote.price, instrument.currency, locale: locale),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.pink),
                  ),
                  if (priceEur != null && instrument.currency != 'EUR')
                    Text(l.pricePerShareEur(formatEur(priceEur, locale: locale)), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l.buy), icon: const Icon(Icons.add)),
              ButtonSegment(value: false, label: Text(l.sell), icon: const Icon(Icons.remove)),
            ],
            selected: {_buy},
            onSelectionChanged: position == null ? null : (s) => setState(() => _buy = s.first),
          ),
          const SizedBox(height: 16),
          if (position != null)
            Text(
              l.youOwn(formatQuantity(position.quantity, locale: locale), formatEur(position.valueEur, locale: locale)),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          Text(l.available(formatEur(cash, locale: locale)), style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: l.amountLabel, prefixText: '€ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in [10.0, 25.0, 50.0])
                ActionChip(label: Text(formatEur(preset, locale: locale, decimals: 0)), onPressed: () => _setAmount(preset)),
              ActionChip(label: Text(l.max), onPressed: () => _setAmount((limit * 100).floor() / 100)),
            ],
          ),
          if (priceEur != null && amount > 0) ...[
            const SizedBox(height: 10),
            Text(l.estimatedShares(formatQuantity(amount / priceEur, locale: locale)), style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: valid && !_busy ? _submit : null,
            style: FilledButton.styleFrom(backgroundColor: _buy ? AppColors.green : AppColors.red),
            child: Text(_buy ? l.confirmBuy(instrument.symbol) : l.confirmSell(instrument.symbol)),
          ),
          if (!_buy && position != null)
            TextButton(onPressed: _busy ? null : () => _submit(sellAll: position), child: Text(l.sellAll)),
          const SizedBox(height: 8),
          Text(l.virtualMoneyNotice, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
