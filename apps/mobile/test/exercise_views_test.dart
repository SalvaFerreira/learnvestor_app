import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnvestor/data/models.dart';
import 'package:learnvestor/features/learn/exercise_views.dart';
import 'package:learnvestor/features/learn/lesson_session.dart';
import 'package:learnvestor/l10n/app_localizations.dart';

/// Hosts an ExerciseView and records the latest response, like LessonScreen does.
class _Host extends StatefulWidget {
  const _Host({required this.exercise, required this.order, required this.onResponse});

  final Exercise exercise;
  final List<int> order;
  final ValueChanged<Object?> onResponse;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Object? _response;

  @override
  Widget build(BuildContext context) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExerciseView(
              exercise: widget.exercise,
              response: _response,
              displayOrder: widget.order,
              revealed: false,
              onChanged: (value) {
                setState(() => _response = value);
                widget.onResponse(value);
              },
            ),
          ),
        ),
      );
}

void main() {
  testWidgets('match: tapping a term then its meaning builds the pairs', (tester) async {
    const exercise = MatchExercise('m',
        prompt: 'Match', left: ['Inflation', 'Deflation', 'ECB'], right: ['Prices up', 'Prices down', 'Central bank'], explanation: '');
    Object? response;
    await tester.pumpWidget(_Host(exercise: exercise, order: const [2, 0, 1], onResponse: (r) => response = r));

    for (final (term, meaning) in [('Inflation', 'Prices up'), ('Deflation', 'Prices down'), ('ECB', 'Central bank')]) {
      await tester.tap(find.text(term));
      await tester.pump();
      await tester.tap(find.text(meaning));
      await tester.pump();
    }
    final pairs = (response as List<int?>).cast<int>().toList();
    expect(pairs, [0, 1, 2]);
    expect(isCorrect(exercise, pairs), isTrue);
  });

  testWidgets('match: a wrong pairing is graded as wrong and can be undone', (tester) async {
    const exercise = MatchExercise('m', prompt: 'Match', left: ['A', 'B', 'C'], right: ['a', 'b', 'c'], explanation: '');
    Object? response;
    await tester.pumpWidget(_Host(exercise: exercise, order: const [0, 1, 2], onResponse: (r) => response = r));

    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pump();
    expect((response as List<int?>)[0], 1);

    await tester.tap(find.text('A')); // unpair
    await tester.pump();
    expect((response as List<int?>)[0], isNull);
  });

  testWidgets('numeric: typed text is parsed and rounded like the answer key', (tester) async {
    const exercise = NumericExercise('n', prompt: '4% - 2,5%?', answer: 1.5, decimals: 1, unit: '%', explanation: '');
    Object? response;
    await tester.pumpWidget(_Host(exercise: exercise, order: const [], onResponse: (r) => response = r));

    await tester.enterText(find.byType(TextField), '1,5');
    await tester.pump();
    expect(response, 1.5);
    expect(isCorrect(exercise, response), isTrue);

    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    expect(isCorrect(exercise, response), isFalse);
  });
}
