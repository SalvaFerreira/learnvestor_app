import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnvestor/data/models.dart';
import 'package:learnvestor/features/learn/lesson_session.dart';

void main() {
  const info = InfoExercise('intro', title: 't', body: 'b');
  const mc = MultipleChoiceExercise('mc', prompt: 'p', options: ['a', 'b', 'c'], answer: 0, explanation: '');
  const tf = TrueFalseExercise('tf', statement: 's', answer: false, explanation: '');
  const order = OrderExercise('order', prompt: 'p', items: ['1', '2', '3'], explanation: '');

  group('isCorrect', () {
    test('compares against the original indexes', () {
      expect(isCorrect(mc, 0), isTrue);
      expect(isCorrect(mc, 1), isFalse);
      expect(isCorrect(tf, false), isTrue);
      expect(isCorrect(order, [0, 1, 2]), isTrue);
      expect(isCorrect(order, [1, 0, 2]), isFalse);
      expect(isCorrect(order, null), isFalse);
      expect(isCorrect(info, null), isTrue);
    });
  });

  group('LessonSession', () {
    test('a perfect run finishes in order and records first answers', () {
      final s = LessonSession([info, mc, tf]);
      expect(s.answer(null), isTrue);
      s.next();
      expect(s.answer(0), isTrue);
      s.next();
      expect(s.answer(false), isTrue);
      s.next();
      expect(s.isFinished, isTrue);
      expect(s.mistakes, 0);
      expect(s.firstAnswers, {'mc': 0, 'tf': false});
      expect(s.progress, 1);
    });

    test('wrong answers are retried at the end but only the first answer is submitted', () {
      final s = LessonSession([mc, tf]);
      expect(s.answer(2), isFalse);
      s.next();
      expect(s.current.id, 'tf');
      expect(s.progress, 0);
      s
        ..answer(false)
        ..next();
      expect(s.current.id, 'mc');
      expect(s.answer(0), isTrue);
      s.next();
      expect(s.isFinished, isTrue);
      expect(s.mistakes, 1);
      expect(s.firstAnswers, {'mc': 2, 'tf': false});
    });
  });

  test('shuffled order exercises never start already solved', () {
    for (var seed = 0; seed < 200; seed++) {
      final order = shuffledIndexes(3, Random(seed), avoidIdentity: true);
      expect(order, isNot(equals([0, 1, 2])));
      expect(order.toSet(), {0, 1, 2});
    }
  });

  test('exercise JSON from start_lesson is parsed into typed exercises', () {
    final ex = Exercise.fromJson({
      'id': 'order',
      'type': 'order',
      'prompt': 'Order these',
      'items': ['a', 'b', 'c'],
      'explanation': 'because',
      'answer': [0, 1, 2],
    });
    expect(ex, isA<OrderExercise>());
    expect((ex as OrderExercise).items, ['a', 'b', 'c']);
    expect(ex.graded, isTrue);
  });
}
