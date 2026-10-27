import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../data/models.dart';

/// Whether [response] answers [exercise] correctly. Responses use the original indexes
/// from the lesson content, so shuffled display order never changes grading.
bool isCorrect(Exercise exercise, Object? response) => switch (exercise) {
      InfoExercise() => true,
      MultipleChoiceExercise(:final answer) => response == answer,
      FillBlankExercise(:final answer) => response == answer,
      TrueFalseExercise(:final answer) => response == answer,
      OrderExercise(:final items) =>
        response is List<int> && listEquals(response, List<int>.generate(items.length, (i) => i)),
      // response[i] = index of the right-hand item paired with left[i]
      MatchExercise(:final left) =>
        response is List<int> && listEquals(response, List<int>.generate(left.length, (i) => i)),
      NumericExercise(:final answer, :final decimals) =>
        response is num && roundTo(response.toDouble(), decimals) == roundTo(answer, decimals),
    };

double roundTo(double value, int decimals) => double.parse(value.toStringAsFixed(decimals));

/// Parses what the learner typed ("1 234,5", "1.234,5" or "1234.5"), rounded like the
/// answer key.
double? parseNumericAnswer(String text, int decimals) {
  var cleaned = text.trim().replaceAll(RegExp(r'[\s€%]'), '');
  if (cleaned.contains(',') && cleaned.contains('.')) cleaned = cleaned.replaceAll('.', '');
  cleaned = cleaned.replaceAll(',', '.');
  final value = double.tryParse(cleaned);
  return value == null ? null : roundTo(value, decimals);
}

/// A random display order for [length] options. For ordering exercises the identity
/// permutation is avoided, otherwise the answer would already be on screen.
List<int> shuffledIndexes(int length, Random random, {bool avoidIdentity = false}) {
  final indexes = List<int>.generate(length, (i) => i)..shuffle(random);
  if (avoidIdentity && length > 1 && listEquals(indexes, List<int>.generate(length, (i) => i))) {
    indexes.add(indexes.removeAt(0));
  }
  return indexes;
}

/// Lesson flow, Duolingo style: wrong answers go back to the end of the queue until
/// they are answered correctly. The server grades only the FIRST answer to each exercise.
class LessonSession {
  LessonSession(this.exercises) : _queue = Queue.of(exercises);

  final List<Exercise> exercises;
  final Queue<Exercise> _queue;
  final Map<String, Object?> _firstAnswers = {};
  final Set<String> _done = {};
  bool? _lastCorrect;
  int mistakes = 0;

  Exercise get current => _queue.first;
  bool get isFinished => _queue.isEmpty;
  double get progress => exercises.isEmpty ? 1 : _done.length / exercises.length;

  /// First answer per graded exercise: the payload for complete_lesson.
  Map<String, Object?> get firstAnswers => Map.unmodifiable(_firstAnswers);

  /// Grades the response to [current]. Call [next] afterwards.
  bool answer(Object? response) {
    final exercise = current;
    final correct = isCorrect(exercise, response);
    if (exercise.graded) _firstAnswers.putIfAbsent(exercise.id, () => response);
    if (!correct) mistakes++;
    _lastCorrect = correct;
    return correct;
  }

  /// Moves on: a correct (or informational) exercise is done, a wrong one is retried later.
  void next() {
    final exercise = _queue.removeFirst();
    if (_lastCorrect ?? true) {
      _done.add(exercise.id);
    } else {
      _queue.addLast(exercise);
    }
    _lastCorrect = null;
  }
}
