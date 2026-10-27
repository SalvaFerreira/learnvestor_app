import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../ui/common.dart';
import 'finance_math.dart';

/// Calculators for real-life money decisions. Pure client-side maths: nothing is stored.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

enum _Tool { compound, emergency, fees }

class _ToolsScreenState extends State<ToolsScreen> {
  _Tool _tool = _Tool.compound;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tools = {
      _Tool.compound: (Icons.trending_up, l.toolCompound, l.toolCompoundDesc),
      _Tool.emergency: (Icons.savings, l.toolEmergency, l.toolEmergencyDesc),
      _Tool.fees: (Icons.percent, l.toolFees, l.toolFeesDesc),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.toolsTitle, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(l.toolsSubtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final MapEntry(key: tool, value: (icon, title, _)) in tools.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(icon, size: 18),
                      label: Text(title),
                      selected: _tool == tool,
                      selectedColor: AppColors.pink,
                      onSelected: (_) => setState(() => _tool = tool),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(tools[_tool]!.$3, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          switch (_tool) {
            _Tool.compound => const _CompoundCalculator(),
            _Tool.emergency => const _EmergencyCalculator(),
            _Tool.fees => const _FeesCalculator(),
          },
          const SizedBox(height: 20),
          Text(l.toolsDisclaimer, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Number field that reports its parsed value (comma or dot decimals).
class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.initial, required this.onChanged, this.decimal = true});

  final String label;
  final num initial;
  final ValueChanged<double> onChanged;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initial.toString(),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))],
        decoration: InputDecoration(labelText: label),
        onChanged: (text) => onChanged(double.tryParse(text.replaceAll(',', '.')) ?? 0),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value, this.color, this.big = false});

  final String label;
  final String value;
  final Color? color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15))),
          Text(value, style: TextStyle(fontSize: big ? 26 : 18, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _CompoundCalculator extends StatefulWidget {
  const _CompoundCalculator();

  @override
  State<_CompoundCalculator> createState() => _CompoundCalculatorState();
}

class _CompoundCalculatorState extends State<_CompoundCalculator> {
  double _initial = 1000;
  double _monthly = 100;
  double _rate = 5;
  double _years = 20;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final years = _years.clamp(1, 60).round();
    final r = compoundGrowth(initial: _initial, monthly: _monthly, annualRatePct: _rate.clamp(0, 30).toDouble(), years: years);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NumberField(label: l.fieldInitial, initial: _initial, onChanged: (v) => setState(() => _initial = v)),
        _NumberField(label: l.fieldMonthly, initial: _monthly, onChanged: (v) => setState(() => _monthly = v)),
        _NumberField(label: l.fieldRate, initial: _rate, onChanged: (v) => setState(() => _rate = v)),
        _NumberField(label: l.fieldYears, initial: _years.round(), decimal: false, onChanged: (v) => setState(() => _years = v)),
        SectionCard(
          child: Column(
            children: [
              _ResultRow(label: l.resultFinal, value: formatEur(r.finalValue, locale: locale, decimals: 0), color: AppColors.green, big: true),
              _ResultRow(label: l.resultContributed, value: formatEur(r.contributed, locale: locale, decimals: 0)),
              _ResultRow(label: l.resultInterest, value: formatEur(r.growth, locale: locale, decimals: 0), color: AppColors.yellow),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [for (final p in r.yearly) FlSpot(p.year.toDouble(), p.value)],
                        isCurved: true,
                        color: AppColors.green,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: true, color: AppColors.green.withValues(alpha: 0.12)),
                      ),
                      LineChartBarData(
                        spots: [for (final p in r.yearly) FlSpot(p.year.toDouble(), p.contributed)],
                        color: AppColors.textSecondary,
                        barWidth: 2,
                        dashArray: [6, 4],
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmergencyCalculator extends StatefulWidget {
  const _EmergencyCalculator();

  @override
  State<_EmergencyCalculator> createState() => _EmergencyCalculatorState();
}

class _EmergencyCalculatorState extends State<_EmergencyCalculator> {
  double _expenses = 900;
  int _months = 6;
  double _saved = 1000;
  double _monthlySaving = 150;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final r = emergencyFund(monthlyExpenses: _expenses, months: _months, saved: _saved, monthlySaving: _monthlySaving);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NumberField(label: l.fieldMonthlyExpenses, initial: _expenses, onChanged: (v) => setState(() => _expenses = v)),
        Text(l.fieldMonths, style: const TextStyle(color: AppColors.textSecondary)),
        Slider(
          value: _months.toDouble(),
          min: 3,
          max: 12,
          divisions: 9,
          label: '$_months',
          onChanged: (v) => setState(() => _months = v.round()),
        ),
        _NumberField(label: l.fieldSaved, initial: _saved, onChanged: (v) => setState(() => _saved = v)),
        _NumberField(label: l.fieldMonthlySaving, initial: _monthlySaving, onChanged: (v) => setState(() => _monthlySaving = v)),
        SectionCard(
          child: Column(
            children: [
              _ResultRow(label: '${l.resultTarget} ($_months × ${formatEur(_expenses, locale: locale, decimals: 0)})',
                  value: formatEur(r.target, locale: locale, decimals: 0), big: true),
              _ResultRow(label: l.resultMissing, value: formatEur(r.missing, locale: locale, decimals: 0), color: AppColors.yellow),
              const SizedBox(height: 8),
              Text(
                r.monthsToGoal == null ? l.resultNeverReached : l.resultMonthsToGoal(r.monthsToGoal!),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.green),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: r.target == 0 ? 1 : ((r.target - r.missing) / r.target).clamp(0, 1).toDouble(),
                  minHeight: 10,
                  color: AppColors.green,
                  backgroundColor: AppColors.surfaceHigh,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeesCalculator extends StatefulWidget {
  const _FeesCalculator();

  @override
  State<_FeesCalculator> createState() => _FeesCalculatorState();
}

class _FeesCalculatorState extends State<_FeesCalculator> {
  double _amount = 10000;
  double _years = 30;
  double _return = 7;
  double _feeA = 0.2;
  double _feeB = 2;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final r = feeImpact(
      amount: _amount,
      years: _years.clamp(1, 60).round(),
      grossReturnPct: _return,
      feeAPct: _feeA,
      feeBPct: _feeB,
    );
    final lossPct = r.withA == 0 ? 0 : r.difference / (r.withA > r.withB ? r.withA : r.withB) * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NumberField(label: l.fieldAmount, initial: _amount, onChanged: (v) => setState(() => _amount = v)),
        _NumberField(label: l.fieldYears, initial: _years.round(), decimal: false, onChanged: (v) => setState(() => _years = v)),
        _NumberField(label: l.fieldRate, initial: _return, onChanged: (v) => setState(() => _return = v)),
        Row(
          children: [
            Expanded(child: _NumberField(label: l.fieldFeeA, initial: _feeA, onChanged: (v) => setState(() => _feeA = v))),
            const SizedBox(width: 12),
            Expanded(child: _NumberField(label: l.fieldFeeB, initial: _feeB, onChanged: (v) => setState(() => _feeB = v))),
          ],
        ),
        SectionCard(
          child: Column(
            children: [
              _ResultRow(label: l.resultWithFeeA, value: formatEur(r.withA, locale: locale, decimals: 0)),
              _ResultRow(label: l.resultWithFeeB, value: formatEur(r.withB, locale: locale, decimals: 0)),
              _ResultRow(
                label: '${l.resultFeeDifference} (${formatPercent(-lossPct, locale: locale)})',
                value: formatEur(r.difference, locale: locale, decimals: 0),
                color: AppColors.red,
                big: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
