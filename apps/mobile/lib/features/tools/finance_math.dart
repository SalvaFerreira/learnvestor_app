import 'dart:math';

/// Future value with monthly compounding and a contribution at the end of every month.
class CompoundResult {
  const CompoundResult({required this.finalValue, required this.contributed, required this.yearly});

  final double finalValue;
  final double contributed;

  /// (year, total value, total contributed) at the end of each year, starting at year 0.
  final List<({int year, double value, double contributed})> yearly;

  double get growth => finalValue - contributed;
}

CompoundResult compoundGrowth({
  required double initial,
  required double monthly,
  required double annualRatePct,
  required int years,
}) {
  final i = annualRatePct / 100 / 12;
  double valueAfter(int months) {
    if (i == 0) return initial + monthly * months;
    final growth = pow(1 + i, months).toDouble();
    return initial * growth + monthly * (growth - 1) / i;
  }

  final yearly = [
    for (var y = 0; y <= years; y++) (year: y, value: valueAfter(y * 12), contributed: initial + monthly * 12 * y),
  ];
  return CompoundResult(finalValue: yearly.last.value, contributed: yearly.last.contributed, yearly: yearly);
}

class EmergencyFundResult {
  const EmergencyFundResult({required this.target, required this.missing, required this.monthsToGoal});

  final double target;
  final double missing;

  /// null when the goal is not reached and nothing is saved per month.
  final int? monthsToGoal;
}

EmergencyFundResult emergencyFund({
  required double monthlyExpenses,
  required int months,
  required double saved,
  required double monthlySaving,
}) {
  final target = monthlyExpenses * months;
  final missing = max(0.0, target - saved);
  final int? monthsToGoal = missing == 0 ? 0 : (monthlySaving > 0 ? (missing / monthlySaving).ceil() : null);
  return EmergencyFundResult(target: target, missing: missing, monthsToGoal: monthsToGoal);
}

/// Final value of a one-off investment under two yearly fee levels (fees are taken out of
/// the gross return every year).
({double withA, double withB, double difference}) feeImpact({
  required double amount,
  required int years,
  required double grossReturnPct,
  required double feeAPct,
  required double feeBPct,
}) {
  double grow(double fee) => amount * pow(1 + (grossReturnPct - fee) / 100, years).toDouble();
  final a = grow(feeAPct);
  final b = grow(feeBPct);
  return (withA: a, withB: b, difference: (a - b).abs());
}
