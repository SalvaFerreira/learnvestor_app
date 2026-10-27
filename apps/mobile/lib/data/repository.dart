import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide toDouble;
import 'package:uuid/uuid.dart';

import '../core/format.dart' show toDouble;
import 'models.dart';

/// Every read and write of game state. Mutations go through RPCs so the server stays
/// authoritative; the only direct table access is read-only reference data and the few
/// profile fields users may edit.
class Repository {
  Repository(this._client);

  final SupabaseClient _client;
  static const _uuid = Uuid();

  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc(fn, params: params) as T;
    } on PostgrestException catch (e) {
      throw AppException.fromCode(e.message);
    }
  }

  Future<PlayerState> getState() async => PlayerState.fromJson(await _rpc<Json>('get_my_state'));

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final uid = _client.auth.currentUser!.id;
    try {
      await _client.from('profiles').update(fields).eq('id', uid);
    } on PostgrestException catch (e) {
      throw AppException.fromCode(e.message);
    }
  }

  Future<List<Track>> getLearningPath(String locale) async {
    final data = await _rpc<List<dynamic>>('get_learning_path', {'p_locale': locale});
    return [for (final t in data) Track.fromJson(t as Json)];
  }

  Future<LessonStart> startLesson(String lessonId, String locale) async =>
      LessonStart.fromJson(await _rpc<Json>('start_lesson', {'p_lesson_id': lessonId, 'p_locale': locale}));

  Future<HeartsInfo> loseHeart(String attemptId) async =>
      HeartsInfo.fromJson(await _rpc<Json>('lose_heart', {'p_attempt_id': attemptId}));

  Future<LessonResult> completeLesson(String attemptId, Map<String, Object?> answers) async =>
      LessonResult.fromJson(await _rpc<Json>('complete_lesson', {'p_attempt_id': attemptId, 'p_answers': answers}));

  /// Practice session from past mistakes; never costs hearts, a good one gives a heart back.
  Future<LessonStart> startPractice(String locale) async =>
      LessonStart.fromJson(await _rpc<Json>('start_practice', {'p_locale': locale}));

  Future<LessonResult> completePractice(String sessionId, Map<String, Object?> answers) async =>
      LessonResult.fromJson(await _rpc<Json>('complete_practice', {'p_session_id': sessionId, 'p_answers': answers}));

  Future<HeartsInfo> refillHearts() async => HeartsInfo.fromJson(await _rpc<Json>('refill_hearts'));

  Future<Portfolio> getPortfolio() async => Portfolio.fromJson(await _rpc<Json>('get_portfolio'));

  /// [amountEur] for buys ("invest €50"), [quantity] for sells (shares).
  Future<void> placeTrade({required String symbol, required bool buy, double? amountEur, double? quantity}) =>
      _rpc<Json>('place_trade', {
        'p_symbol': symbol,
        'p_side': buy ? 'buy' : 'sell',
        'p_idempotency_key': _uuid.v4(),
        'p_amount_eur': amountEur,
        'p_quantity': quantity,
      });

  Future<List<Instrument>> getInstruments() async {
    final rows = await _client
        .from('instruments')
        .select('symbol, name, exchange, currency, sector, logo_url')
        .eq('is_active', true)
        .order('popularity', ascending: false);
    return [for (final r in rows) Instrument.fromJson(r)];
  }

  /// The sample quotes (they do not change while the demo is open).
  Future<Map<String, Quote>> getQuotes() async {
    final rows = await _client.from('quotes_latest').select('symbol, price, change_pct, as_of');
    return {for (final r in rows) r['symbol'] as String: Quote.fromJson(r)};
  }

  /// Units of each currency per 1 EUR.
  Future<Map<String, double>> getFxRates() async {
    final rows = await _client.from('fx_rates').select('currency, rate_per_eur');
    return {'EUR': 1, for (final r in rows) r['currency'] as String: toDouble(r['rate_per_eur'])};
  }

  Future<List<Achievement>> getAchievements(String locale) async {
    final data = await _rpc<List<dynamic>>('get_my_achievements', {'p_locale': locale});
    return [for (final a in data) Achievement.fromJson(a as Json)];
  }

  /// "Reset progress": deletes the anonymous user and, by cascade, all of their data.
  Future<void> resetProgress() async {
    final res = await _client.functions.invoke('delete-account', method: HttpMethod.post);
    if (res.status != 200) throw const AppException(AppError.unknown);
  }
}

enum AppError {
  notAuthenticated,
  lessonLocked,
  lessonNotFound,
  outOfHearts,
  tooFast,
  rateLimited,
  attemptClosed,
  insufficientGems,
  heartsFull,
  insufficientCash,
  insufficientShares,
  amountTooSmall,
  quoteUnavailable,
  nothingToPractice,
  invalidProfile,
  timezoneChangeTooSoon,
  network,
  unknown,
}

class AppException implements Exception {
  const AppException(this.error, [this.code]);

  /// Maps the snake_case messages raised by the database functions.
  factory AppException.fromCode(String code) => AppException(
        switch (code) {
          'not_authenticated' => AppError.notAuthenticated,
          'lesson_locked' => AppError.lessonLocked,
          'lesson_not_found' => AppError.lessonNotFound,
          'out_of_hearts' => AppError.outOfHearts,
          'too_fast' => AppError.tooFast,
          'rate_limited' => AppError.rateLimited,
          'attempt_closed' || 'attempt_not_found' => AppError.attemptClosed,
          'insufficient_gems' => AppError.insufficientGems,
          'hearts_full' => AppError.heartsFull,
          'insufficient_cash' => AppError.insufficientCash,
          'insufficient_shares' => AppError.insufficientShares,
          'amount_too_small' || 'invalid_amount' || 'invalid_quantity' => AppError.amountTooSmall,
          'quote_unavailable' || 'fx_unavailable' || 'unknown_symbol' => AppError.quoteUnavailable,
          'nothing_to_practice' => AppError.nothingToPractice,
          'invalid_profile' => AppError.invalidProfile,
          'timezone_change_too_soon' => AppError.timezoneChangeTooSoon,
          _ => AppError.unknown,
        },
        code,
      );

  final AppError error;
  final String? code;

  @override
  String toString() => 'AppException($error, $code)';
}
