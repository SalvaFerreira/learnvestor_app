import '../core/format.dart';

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

// ---- player state (get_my_state) -------------------------------------------------------

class Profile {
  const Profile({
    required this.id,
    required this.locale,
    required this.timezone,
    required this.dailyGoalXp,
    this.countryCode,
  });

  factory Profile.fromJson(Json j) => Profile(
        id: j['id'] as String,
        locale: j['locale'] as String,
        timezone: j['timezone'] as String,
        dailyGoalXp: toInt(j['daily_goal_xp']),
        countryCode: j['country_code'] as String?,
      );

  final String id;
  final String locale;
  final String timezone;
  final int dailyGoalXp;
  final String? countryCode;
}

class Stats {
  const Stats({
    required this.xp,
    required this.level,
    required this.levelXpStart,
    required this.levelXpNext,
    required this.gems,
    required this.hearts,
    required this.maxHearts,
    required this.nextHeartAt,
    required this.streak,
    required this.streakLongest,
    required this.streakExtendedToday,
    required this.lessonsCompleted,
    required this.coinsEarned,
    required this.xpToday,
  });

  factory Stats.fromJson(Json j) => Stats(
        xp: toInt(j['xp']),
        level: toInt(j['level']),
        levelXpStart: toInt(j['level_xp_start']),
        levelXpNext: toInt(j['level_xp_next']),
        gems: toInt(j['gems']),
        hearts: toInt(j['hearts']),
        maxHearts: toInt(j['max_hearts']),
        nextHeartAt: _date(j['next_heart_at']),
        streak: toInt(j['streak']),
        streakLongest: toInt(j['streak_longest']),
        streakExtendedToday: j['streak_extended_today'] as bool? ?? false,
        lessonsCompleted: toInt(j['lessons_completed']),
        coinsEarned: toDouble(j['coins_earned']),
        xpToday: toInt(j['xp_today']),
      );

  final int xp;
  final int level;
  final int levelXpStart;
  final int levelXpNext;
  final int gems;
  final int hearts;
  final int maxHearts;
  final DateTime? nextHeartAt;
  final int streak;
  final int streakLongest;
  final bool streakExtendedToday;
  final int lessonsCompleted;
  final double coinsEarned;
  final int xpToday;

  double get levelProgress =>
      levelXpNext <= levelXpStart ? 0 : ((xp - levelXpStart) / (levelXpNext - levelXpStart)).clamp(0, 1);
  int get xpToNextLevel => levelXpNext - xp;
}

class Economy {
  const Economy({
    required this.refillHeartsGemCost,
    required this.minTradeEur,
  });

  factory Economy.fromJson(Json j) => Economy(
        refillHeartsGemCost: toInt(j['refill_hearts_gem_cost']),
        minTradeEur: toDouble(j['min_trade_eur']),
      );

  final int refillHeartsGemCost;
  final double minTradeEur;
}

class PlayerState {
  const PlayerState({
    required this.profile,
    required this.stats,
    required this.cash,
    required this.holdingsValue,
    required this.totalValue,
    required this.economy,
  });

  factory PlayerState.fromJson(Json j) {
    final portfolio = j['portfolio'] as Json;
    return PlayerState(
      profile: Profile.fromJson(j['profile'] as Json),
      stats: Stats.fromJson(j['stats'] as Json),
      cash: toDouble(portfolio['cash']),
      holdingsValue: toDouble(portfolio['holdings_value']),
      totalValue: toDouble(portfolio['total_value']),
      economy: Economy.fromJson(j['economy'] as Json),
    );
  }

  final Profile profile;
  final Stats stats;
  final double cash;
  final double holdingsValue;
  final double totalValue;
  final Economy economy;
}

class HeartsInfo {
  const HeartsInfo({required this.hearts, required this.maxHearts, required this.gems, this.nextHeartAt});

  factory HeartsInfo.fromJson(Json j) => HeartsInfo(
        hearts: toInt(j['hearts']),
        maxHearts: toInt(j['max_hearts']),
        gems: toInt(j['gems']),
        nextHeartAt: _date(j['next_heart_at']),
      );

  final int hearts;
  final int maxHearts;
  final int gems;
  final DateTime? nextHeartAt;

  bool get isEmpty => hearts <= 0;
}

// ---- learning path -----------------------------------------------------------------------

enum LessonStatus { completed, unlocked, locked }

class LessonNode {
  const LessonNode({
    required this.id,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.coinReward,
    required this.status,
    this.stars,
  });

  factory LessonNode.fromJson(Json j) => LessonNode(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        xpReward: toInt(j['xp_reward']),
        coinReward: toDouble(j['coin_reward']),
        status: LessonStatus.values.byName(j['status'] as String),
        stars: j['stars'] == null ? null : toInt(j['stars']),
      );

  final String id;
  final String title;
  final String description;
  final int xpReward;
  final double coinReward;
  final LessonStatus status;
  final int? stars;

  bool get playable => status == LessonStatus.completed || status == LessonStatus.unlocked;
}

class UnitNode {
  const UnitNode({required this.id, required this.title, required this.description, required this.lessons});

  factory UnitNode.fromJson(Json j) => UnitNode(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        lessons: [for (final l in j['lessons'] as List) LessonNode.fromJson(l as Json)],
      );

  final String id;
  final String title;
  final String description;
  final List<LessonNode> lessons;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.starsEarned,
    required this.starsTotal,
    required this.units,
  });

  factory Track.fromJson(Json j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        icon: j['icon'] as String,
        color: j['color'] as String,
        starsEarned: toInt(j['stars_earned']),
        starsTotal: toInt(j['stars_total']),
        units: [for (final u in j['units'] as List) UnitNode.fromJson(u as Json)],
      );

  final String id;
  final String title;
  final String description;
  final String icon;
  final String color;
  final int starsEarned;
  final int starsTotal;
  final List<UnitNode> units;

  Iterable<LessonNode> get lessons => units.expand((u) => u.lessons);
  double get completion => starsTotal == 0 ? 0 : starsEarned / starsTotal;
}

// ---- lessons -----------------------------------------------------------------------------

sealed class Exercise {
  const Exercise(this.id);

  factory Exercise.fromJson(Json j) {
    final id = j['id'] as String;
    final explanation = j['explanation'] as String? ?? '';
    List<String> strings(String key) => [for (final s in j[key] as List) s as String];
    return switch (j['type']) {
      'info' => InfoExercise(id, title: j['title'] as String, body: j['body'] as String),
      'multiple_choice' => MultipleChoiceExercise(id,
          prompt: j['prompt'] as String, options: strings('options'), answer: toInt(j['answer']), explanation: explanation),
      'true_false' => TrueFalseExercise(id,
          statement: j['statement'] as String, answer: j['answer'] as bool, explanation: explanation),
      'fill_blank' => FillBlankExercise(id,
          sentence: j['sentence'] as String, options: strings('options'), answer: toInt(j['answer']), explanation: explanation),
      'order' => OrderExercise(id, prompt: j['prompt'] as String, items: strings('items'), explanation: explanation),
      'match' => MatchExercise(id,
          prompt: j['prompt'] as String, left: strings('left'), right: strings('right'), explanation: explanation),
      'numeric' => NumericExercise(id,
          prompt: j['prompt'] as String,
          answer: toDouble(j['answer']),
          decimals: toInt(j['decimals']),
          unit: j['unit'] as String?,
          explanation: explanation),
      final other => throw FormatException('Unknown exercise type $other'),
    };
  }

  final String id;

  /// Info cards are read, not answered.
  bool get graded => this is! InfoExercise;
}

class InfoExercise extends Exercise {
  const InfoExercise(super.id, {required this.title, required this.body});
  final String title;
  final String body;
}

class MultipleChoiceExercise extends Exercise {
  const MultipleChoiceExercise(super.id, {required this.prompt, required this.options, required this.answer, required this.explanation});
  final String prompt;
  final List<String> options;
  final int answer;
  final String explanation;
}

class TrueFalseExercise extends Exercise {
  const TrueFalseExercise(super.id, {required this.statement, required this.answer, required this.explanation});
  final String statement;
  final bool answer;
  final String explanation;
}

class FillBlankExercise extends Exercise {
  const FillBlankExercise(super.id, {required this.sentence, required this.options, required this.answer, required this.explanation});
  final String sentence;
  final List<String> options;
  final int answer;
  final String explanation;
}

/// Items arrive in the correct order; the app shuffles them for display.
class OrderExercise extends Exercise {
  const OrderExercise(super.id, {required this.prompt, required this.items, required this.explanation});
  final String prompt;
  final List<String> items;
  final String explanation;
}

/// Pairs to connect: left[i] matches right[i]. The app shuffles the right column.
class MatchExercise extends Exercise {
  const MatchExercise(super.id, {required this.prompt, required this.left, required this.right, required this.explanation});
  final String prompt;
  final List<String> left;
  final List<String> right;
  final String explanation;
}

/// A small calculation; the answer is compared after rounding to [decimals].
class NumericExercise extends Exercise {
  const NumericExercise(super.id,
      {required this.prompt, required this.answer, required this.decimals, required this.explanation, this.unit});
  final String prompt;
  final double answer;
  final int decimals;
  final String? unit;
  final String explanation;
}

/// A lesson attempt or a practice session (lessonId is null for practice, where each
/// exercise id is "lessonId/exerciseId").
class LessonStart {
  const LessonStart({
    required this.attemptId,
    required this.lessonId,
    required this.title,
    required this.exercises,
    required this.hearts,
  });

  factory LessonStart.fromJson(Json j) => LessonStart(
        attemptId: j['attempt_id'] as String,
        lessonId: j['lesson_id'] as String?,
        title: j['title'] as String? ?? '',
        exercises: [for (final e in j['exercises'] as List) Exercise.fromJson(e as Json)],
        hearts: HeartsInfo.fromJson(j['hearts'] as Json),
      );

  final String attemptId;
  final String? lessonId;
  final String title;
  final List<Exercise> exercises;
  final HeartsInfo hearts;
}

class LessonResult {
  const LessonResult({
    required this.status,
    this.stars = 0,
    this.correct = 0,
    this.total = 0,
    this.xpAwarded = 0,
    this.coinsAwarded = 0,
    this.level = 1,
    this.leveledUp = false,
    this.firstCompletion = false,
    this.streak = 0,
    this.streakExtendedToday = false,
    this.newAchievements = const [],
    this.hearts,
    this.heartAwarded = false,
  });

  factory LessonResult.fromJson(Json j) {
    final streak = j['streak'] as Json?;
    return LessonResult(
      status: j['status'] as String,
      stars: toInt(j['stars']),
      correct: toInt(j['correct']),
      total: toInt(j['total']),
      xpAwarded: toInt(j['xp_awarded']),
      coinsAwarded: toDouble(j['coins_awarded']),
      level: toInt(j['level']),
      leveledUp: j['leveled_up'] as bool? ?? false,
      firstCompletion: j['first_completion'] as bool? ?? false,
      streak: toInt(streak?['current']),
      streakExtendedToday: streak?['extended_today'] as bool? ?? false,
      newAchievements: [for (final a in (j['new_achievements'] as List?) ?? const []) a as String],
      hearts: j['hearts'] == null ? null : HeartsInfo.fromJson(j['hearts'] as Json),
      heartAwarded: j['heart_awarded'] as bool? ?? false,
    );
  }

  final String status;
  final int stars;
  final int correct;
  final int total;
  final int xpAwarded;
  final double coinsAwarded;
  final int level;
  final bool leveledUp;
  final bool firstCompletion;
  final int streak;
  final bool streakExtendedToday;
  final List<String> newAchievements;
  final HeartsInfo? hearts;

  /// Practice only: a good session gave one heart back.
  final bool heartAwarded;

  bool get completed => status == 'completed';
}

// ---- market & portfolio -----------------------------------------------------------------

class Instrument {
  const Instrument({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.currency,
    required this.sector,
    this.logoUrl,
  });

  factory Instrument.fromJson(Json j) => Instrument(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        exchange: j['exchange'] as String,
        currency: j['currency'] as String,
        sector: j['sector'] as String,
        logoUrl: j['logo_url'] as String?,
      );

  final String symbol;
  final String name;
  final String exchange;
  final String currency;
  final String sector;
  final String? logoUrl;
}

class Quote {
  const Quote({required this.symbol, required this.price, required this.changePct, required this.asOf});

  factory Quote.fromJson(Json j) => Quote(
        symbol: j['symbol'] as String,
        price: toDouble(j['price']),
        changePct: j['change_pct'] == null ? null : toDouble(j['change_pct']),
        asOf: _date(j['as_of'])!,
      );

  final String symbol;
  final double price;
  final double? changePct;
  final DateTime asOf;
}

class Position {
  const Position({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.costBasisEur,
    required this.valueEur,
    required this.currency,
    this.logoUrl,
    this.price,
    this.changePct,
  });

  factory Position.fromJson(Json j) => Position(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        quantity: toDouble(j['quantity']),
        costBasisEur: toDouble(j['cost_basis_eur']),
        valueEur: toDouble(j['value_eur']),
        currency: j['currency'] as String,
        logoUrl: j['logo_url'] as String?,
        price: j['price'] == null ? null : toDouble(j['price']),
        changePct: j['change_pct'] == null ? null : toDouble(j['change_pct']),
      );

  final String symbol;
  final String name;
  final double quantity;
  final double costBasisEur;
  final double valueEur;
  final String currency;
  final String? logoUrl;
  final double? price;
  final double? changePct;

  double get pnl => valueEur - costBasisEur;
  double get pnlPct => costBasisEur == 0 ? 0 : pnl / costBasisEur * 100;
}

class HistoryPoint {
  const HistoryPoint(this.day, this.value);
  final DateTime day;
  final double value;
}

class TradeSummary {
  const TradeSummary({required this.symbol, required this.side, required this.quantity, required this.amountEur, required this.executedAt});

  factory TradeSummary.fromJson(Json j) => TradeSummary(
        symbol: j['symbol'] as String,
        side: j['side'] as String,
        quantity: toDouble(j['quantity']),
        amountEur: toDouble(j['amount_eur']),
        executedAt: _date(j['executed_at'])!,
      );

  final String symbol;
  final String side;
  final double quantity;
  final double amountEur;
  final DateTime executedAt;
}

class Portfolio {
  const Portfolio({
    required this.cash,
    required this.holdingsValue,
    required this.totalValue,
    required this.positions,
    required this.history,
    required this.recentTrades,
  });

  factory Portfolio.fromJson(Json j) => Portfolio(
        cash: toDouble(j['cash']),
        holdingsValue: toDouble(j['holdings_value']),
        totalValue: toDouble(j['total_value']),
        positions: [for (final p in j['positions'] as List) Position.fromJson(p as Json)],
        history: [
          for (final h in j['history'] as List)
            HistoryPoint(DateTime.parse((h as Json)['day'] as String), toDouble(h['value'])),
        ],
        recentTrades: [for (final t in j['recent_trades'] as List) TradeSummary.fromJson(t as Json)],
      );

  final double cash;
  final double holdingsValue;
  final double totalValue;
  final List<Position> positions;
  final List<HistoryPoint> history;
  final List<TradeSummary> recentTrades;

  Position? positionFor(String symbol) {
    for (final p in positions) {
      if (p.symbol == symbol) return p;
    }
    return null;
  }
}

// ---- social -------------------------------------------------------------------------------

class Achievement {
  const Achievement({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.threshold,
    required this.progress,
    required this.gemReward,
    this.unlockedAt,
  });

  factory Achievement.fromJson(Json j) => Achievement(
        id: j['id'] as String,
        icon: j['icon'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        threshold: toInt(j['threshold']),
        progress: toInt(j['progress']),
        gemReward: toInt(j['gem_reward']),
        unlockedAt: _date(j['unlocked_at']),
      );

  final String id;
  final String icon;
  final String title;
  final String description;
  final int threshold;
  final int progress;
  final int gemReward;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;
}
