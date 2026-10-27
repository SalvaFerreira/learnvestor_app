import 'package:flutter_test/flutter_test.dart';
import 'package:learnvestor/features/learn/lesson_session.dart';
import 'package:learnvestor/features/tools/finance_math.dart';

void main() {
  group('compoundGrowth', () {
    test('matches the closed-form future value', () {
      final r = compoundGrowth(initial: 1000, monthly: 100, annualRatePct: 6, years: 10);
      // 1000·1.005^120 + 100·(1.005^120 − 1)/0.005
      expect(r.finalValue, closeTo(18207.34, 0.5));
      expect(r.contributed, 13000);
      expect(r.yearly, hasLength(11));
      expect(r.yearly.first.value, 1000);
    });

    test('works with a zero rate', () {
      final r = compoundGrowth(initial: 500, monthly: 50, annualRatePct: 0, years: 2);
      expect(r.finalValue, 1700);
      expect(r.growth, 0);
    });
  });

  test('emergencyFund', () {
    final r = emergencyFund(monthlyExpenses: 1000, months: 6, saved: 2500, monthlySaving: 400);
    expect(r.target, 6000);
    expect(r.missing, 3500);
    expect(r.monthsToGoal, 9); // 3500 / 400 = 8.75
    expect(emergencyFund(monthlyExpenses: 1000, months: 3, saved: 5000, monthlySaving: 0).monthsToGoal, 0);
    expect(emergencyFund(monthlyExpenses: 1000, months: 3, saved: 0, monthlySaving: 0).monthsToGoal, isNull);
  });

  test('feeImpact matches the lesson example (≈40% less after 30 years)', () {
    final r = feeImpact(amount: 10000, years: 30, grossReturnPct: 7.2, feeAPct: 0.2, feeBPct: 2);
    expect(r.withA, closeTo(76122.55, 1));
    expect(r.difference / r.withA, closeTo(0.40, 0.01));
  });

  group('numeric answers', () {
    test('accept Portuguese and English formats', () {
      expect(parseNumericAnswer('1 234,5', 1), 1234.5);
      expect(parseNumericAnswer('1.234,56', 2), 1234.56);
      expect(parseNumericAnswer('121', 0), 121);
      expect(parseNumericAnswer('121.4', 0), 121);
      expect(parseNumericAnswer('€ 30', 0), 30);
      expect(parseNumericAnswer('abc', 0), isNull);
    });
  });
}
