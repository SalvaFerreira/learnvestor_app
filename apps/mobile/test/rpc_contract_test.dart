// Parses real RPC responses produced by the database (tools/db-tests/fixtures.mjs) with the
// app's models, so a change in an RPC's JSON shape breaks this test instead of the app.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnvestor/data/models.dart';
import 'package:learnvestor/features/learn/lesson_session.dart';

Object? fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  test('get_my_state', () {
    final state = PlayerState.fromJson(fixture('get_my_state')! as Json);
    expect(state.profile.locale, 'pt');
    expect(state.stats.lessonsCompleted, 1);
    expect(state.stats.hearts, state.stats.maxHearts, reason: 'the practice session gave back the heart lost in the lesson');
    expect(state.stats.levelProgress, inInclusiveRange(0, 1));
    expect(state.totalValue, closeTo(state.cash + state.holdingsValue, 0.01));
  });

  test('get_learning_path', () {
    final tracks = [for (final t in fixture('get_learning_path')! as List) Track.fromJson(t as Json)];
    expect(tracks.map((t) => t.id), ['banks', 'taxes', 'investment', 'mindset', 'advanced']);
    final banks = tracks.first.lessons.toList();
    expect(banks.first.status, LessonStatus.completed);
    expect(banks.first.stars, 2);
    expect(banks[1].status, LessonStatus.unlocked);
    expect(tracks.last.lessons.first.status, LessonStatus.unlocked, reason: 'every track is free');
  });

  test('start_lesson → a LessonSession that the answer key solves', () {
    final start = LessonStart.fromJson(fixture('start_lesson')! as Json);
    expect(start.title, 'Como Funcionam os Bancos');
    expect(start.exercises.whereType<InfoExercise>(), hasLength(1));
    expect(start.hearts.maxHearts, greaterThan(0));

    final raw = (fixture('start_lesson')! as Json)['exercises'] as List;
    final session = LessonSession(start.exercises);
    for (final e in raw.cast<Json>()) {
      final answer = e['answer'] is List ? (e['answer'] as List).cast<int>() : e['answer'];
      expect(session.answer(answer), isTrue, reason: 'server answer for ${e['id']} must be accepted by the app');
      session.next();
    }
    expect(session.isFinished, isTrue);
  });

  test('lose_heart and complete_lesson', () {
    final hearts = HeartsInfo.fromJson(fixture('lose_heart')! as Json);
    expect(hearts.nextHeartAt, isNotNull);

    final result = LessonResult.fromJson(fixture('complete_lesson')! as Json);
    expect(result.completed, isTrue);
    expect(result.correct, result.total - 1);
    expect(result.coinsAwarded, 30);
    expect(result.streak, 1);
    expect(result.newAchievements, contains('first_lesson'));
  });

  test('start_practice / complete_practice', () {
    final start = LessonStart.fromJson(fixture('start_practice')! as Json);
    expect(start.lessonId, isNull);
    expect(start.exercises.first.id, 'what-is-a-bank/deposit-guarantee', reason: 'past mistakes come first');
    final raw = (fixture('start_practice')! as Json)['exercises'] as List;
    final session = LessonSession(start.exercises);
    for (final e in raw.cast<Json>()) {
      final answer = e['answer'] is List ? (e['answer'] as List).cast<int>() : e['answer'];
      expect(session.answer(answer), isTrue);
      session.next();
    }
    final result = LessonResult.fromJson(fixture('complete_practice')! as Json);
    expect(result.completed, isTrue);
    expect(result.correct, result.total);
    expect(result.coinsAwarded, 0);
    expect(result.hearts, isNotNull);
  });

  test('get_portfolio', () {
    final portfolio = Portfolio.fromJson(fixture('get_portfolio')! as Json);
    expect(portfolio.positions.map((p) => p.symbol), containsAll(['AAPL', 'GALP.LS']));
    expect(portfolio.positionFor('GALP.LS')!.quantity, 1.5);
    expect(portfolio.recentTrades, hasLength(2));
    expect(portfolio.history, isNotEmpty);
    expect(portfolio.totalValue, closeTo(portfolio.cash + portfolio.holdingsValue, 0.01));
  });

  test('achievements', () {
    final achievements = [for (final a in fixture('get_my_achievements')! as List) Achievement.fromJson(a as Json)];
    expect(achievements.firstWhere((a) => a.id == 'first_lesson').unlocked, isTrue);
    expect(achievements.firstWhere((a) => a.id == 'first_trade').title, 'Primeira Transação');
  });
}
