import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnvestor/l10n/app_localizations.dart';

void main() {
  // Portuguese plural rules put 0 in the same category as 1, so every PT plural needs an
  // explicit =0 form or "0" is shown as "1 dia".
  test('Portuguese plurals show zero as zero', () {
    final pt = lookupAppLocalizations(const Locale('pt'));
    expect(pt.streakDays(0), 'Sequência de 0 dias');
    expect(pt.longestStreak(0), 'Mais longa: 0 dias');
    expect(pt.holdings(0), '0 posições');
    expect(pt.streakDays(1), 'Sequência de 1 dia');
    expect(pt.streakDays(2), 'Sequência de 2 dias');
  });
}
