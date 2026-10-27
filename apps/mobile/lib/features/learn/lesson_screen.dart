import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';
import 'exercise_views.dart';
import 'lesson_session.dart';

/// Plays a lesson, or a practice session when [lessonId] is null. Practice uses the same
/// flow but never costs hearts and is graded by complete_practice.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required String this.lessonId});

  const LessonScreen.practice({super.key}) : lessonId = null;

  final String? lessonId;

  bool get isPractice => lessonId == null;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  final _random = Random();
  final _displayOrders = <String, List<int>>{};

  LessonStart? _start;
  LessonSession? _session;
  HeartsInfo? _hearts;
  Object? _loadError;

  Object? _response;
  bool? _lastCorrect; // null while the current exercise has not been checked

  bool _submitting = false;
  Object? _submitError;
  LessonResult? _result;

  Repository get _repo => ref.read(repositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final locale = ref.read(contentLocaleProvider);
      final start =
          widget.isPractice ? await _repo.startPractice(locale) : await _repo.startLesson(widget.lessonId!, locale);
      if (!mounted) return;
      setState(() {
        _start = start;
        _session = LessonSession(start.exercises);
        _hearts = start.hearts;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  List<int> _orderFor(Exercise exercise) => _displayOrders.putIfAbsent(exercise.id, () {
        return switch (exercise) {
          MultipleChoiceExercise(:final options) || FillBlankExercise(:final options) => shuffledIndexes(options.length, _random),
          OrderExercise(:final items) => shuffledIndexes(items.length, _random, avoidIdentity: true),
          MatchExercise(:final right) => shuffledIndexes(right.length, _random, avoidIdentity: true),
          _ => const [],
        };
      });

  bool get _canCheck {
    final exercise = _session!.current;
    return switch (exercise) {
      InfoExercise() => true,
      OrderExercise(:final items) => (_response as List<int>?)?.length == items.length,
      MatchExercise() => (_response as List<int?>?)?.every((p) => p != null) ?? false,
      _ => _response != null,
    };
  }

  void _check() {
    final session = _session!;
    if (session.current is InfoExercise) {
      session
        ..answer(null)
        ..next();
      _advance();
      return;
    }
    // Pairs are built as List<int?>; once complete they are submitted as List<int>.
    final response = session.current is MatchExercise ? (_response as List<int?>).cast<int>().toList() : _response;
    final correct = session.answer(response);
    setState(() => _lastCorrect = correct);
    if (!correct && !widget.isPractice) _loseHeart();
  }

  Future<void> _loseHeart() async {
    try {
      final hearts = await _repo.loseHeart(_start!.attemptId);
      if (mounted) setState(() => _hearts = hearts);
    } catch (_) {
      // Not critical: complete_lesson reconciles hearts for every mistake anyway.
    }
  }

  Future<void> _continue() async {
    if (_hearts?.isEmpty ?? false) {
      final resumed = await _showOutOfHearts();
      if (!resumed) return;
    }
    final answered = _session!.current;
    _session!.next();
    // A wrong exercise comes back later with a fresh shuffle.
    if (_lastCorrect == false) _displayOrders.remove(answered.id);
    _advance();
  }

  void _advance() {
    setState(() {
      _response = null;
      _lastCorrect = null;
    });
    if (_session!.isFinished) _finish();
  }

  Future<void> _finish() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = widget.isPractice
          ? await _repo.completePractice(_start!.attemptId, _session!.firstAnswers)
          : await _repo.completeLesson(_start!.attemptId, _session!.firstAnswers);
      refreshAfterLesson(ref);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _submitError = e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Returns true when the learner can keep going (refilled or became Plus). Choosing
  /// practice replaces this lesson with a practice session.
  Future<bool> _showOutOfHearts() async {
    final choice = await showModalBottomSheet<_OutOfHeartsChoice>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _OutOfHeartsSheet(hearts: _hearts!),
    );
    if (choice == _OutOfHeartsChoice.practice) {
      if (mounted) context.pushReplacement('/practice');
      return false;
    }
    if (choice == _OutOfHeartsChoice.resume) {
      final state = await ref.read(playerStateProvider.future);
      if (mounted && state != null) {
        setState(() => _hearts = HeartsInfo(
              hearts: state.stats.hearts,
              maxHearts: state.stats.maxHearts,
              unlimited: state.isPlus,
              gems: state.stats.gems,
            ));
      }
      return !(_hearts?.isEmpty ?? true);
    }
    if (mounted) context.pop();
    return false;
  }

  Future<void> _confirmQuit() async {
    final l = context.l10n;
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.quitLessonTitle),
        content: Text(l.quitLessonBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l.quit)),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(l.keepLearning)),
        ],
      ),
    );
    if (quit == true && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_loadError != null) return _LoadError(error: _loadError!, onRetry: _load);
    if (_result != null) return _ResultView(result: _result!, practice: widget.isPractice);
    if (_session == null || _submitting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_submitting) ...[const SizedBox(height: 16), Text(l.saving)],
            ],
          ),
        ),
      );
    }
    if (_submitError != null) {
      return _LoadError(error: _submitError!, onRetry: _finish);
    }

    final session = _session!;
    final exercise = session.current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: _confirmQuit, icon: const Icon(Icons.close)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: session.progress),
                          duration: const Duration(milliseconds: 300),
                          builder: (_, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 14,
                            color: AppColors.green,
                            backgroundColor: AppColors.surfaceHigh,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    HeartsBadge.fromInfo(_hearts!),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: ExerciseView(
                    key: ValueKey('${exercise.id}-${session.mistakes}'),
                    exercise: exercise,
                    response: _response,
                    displayOrder: _orderFor(exercise),
                    revealed: _lastCorrect != null,
                    onChanged: (value) => setState(() => _response = value),
                  ),
                ),
              ),
              if (_lastCorrect == null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: FilledButton(
                    onPressed: _canCheck ? _check : null,
                    child: Text(exercise is InfoExercise ? l.continueLabel : l.check),
                  ),
                )
              else
                _FeedbackPanel(
                  correct: _lastCorrect!,
                  exercise: exercise,
                  onContinue: _continue,
                  onReport: () => _report(exercise),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Report a problem" for the exercise just answered (feeds content_reports).
  Future<void> _report(Exercise exercise) async {
    // Practice exercise ids are "<lesson id>/<exercise id>".
    final parts = exercise.id.split('/');
    final lessonId = widget.isPractice ? parts.first : widget.lessonId!;
    final exerciseId = parts.last;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportSheet(lessonId: lessonId, exerciseId: exerciseId),
    );
    if (sent == true && mounted) showMessage(context, context.l10n.reportThanks);
  }
}

enum _OutOfHeartsChoice { resume, practice }

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.lessonId, required this.exerciseId});

  final String lessonId;
  final String exerciseId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _message = TextEditingController();
  String _reason = 'wrong_answer';
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).reportContent(
            lessonId: widget.lessonId,
            exerciseId: widget.exerciseId,
            reason: _reason,
            message: _message.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.reportProblem, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v!),
            child: Column(
              children: [
                for (final (value, label) in [
                  ('wrong_answer', l.reportReasonWrongAnswer),
                  ('typo', l.reportReasonTypo),
                  ('unclear', l.reportReasonUnclear),
                  ('other', l.reportReasonOther),
                ])
                  RadioListTile<String>(value: value, title: Text(label), contentPadding: EdgeInsets.zero),
              ],
            ),
          ),
          TextField(
            controller: _message,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(hintText: l.reportMessageHint),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _send, child: Text(l.reportSend)),
        ],
      ),
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({required this.correct, required this.exercise, required this.onContinue, required this.onReport});

  final bool correct;
  final Exercise exercise;
  final VoidCallback onContinue;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final color = correct ? AppColors.green : AppColors.red;
    final explanation = explanationOf(exercise);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(top: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(correct ? Icons.check_circle : Icons.cancel, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(correct ? l.correct : l.incorrect,
                    style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: l.reportProblem,
                onPressed: onReport,
                icon: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
              ),
            ],
          ),
          if (!correct) ...[
            const SizedBox(height: 8),
            Text(l.correctAnswerWas(correctAnswerText(context, exercise)), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(explanation, style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: onContinue,
            child: Text(l.continueLabel),
          ),
        ],
      ),
    );
  }
}

class _OutOfHeartsSheet extends ConsumerStatefulWidget {
  const _OutOfHeartsSheet({required this.hearts});

  final HeartsInfo hearts;

  @override
  ConsumerState<_OutOfHeartsSheet> createState() => _OutOfHeartsSheetState();
}

class _OutOfHeartsSheetState extends ConsumerState<_OutOfHeartsSheet> {
  bool _busy = false;

  Future<void> _refill() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).refillHearts();
      ref.invalidate(playerStateProvider);
      if (mounted) Navigator.pop(context, _OutOfHeartsChoice.resume);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _plus() async {
    await context.push('/plus');
    ref.invalidate(playerStateProvider);
    final state = await ref.read(playerStateProvider.future);
    if (mounted && (state?.isPlus ?? false)) Navigator.pop(context, _OutOfHeartsChoice.resume);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final economy = ref.watch(playerStateProvider).value?.economy;
    final cost = economy?.refillHeartsGemCost ?? 0;
    final next = widget.hearts.nextHeartAt;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.heart_broken, color: AppColors.red, size: 56),
            const SizedBox(height: 12),
            Text(l.outOfHeartsTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(l.outOfHeartsBody, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            if (next != null) ...[
              const SizedBox(height: 8),
              Text(
                l.nextHeartIn(max(1, next.difference(DateTime.now()).inMinutes)),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.pink),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy || widget.hearts.gems < cost ? null : _refill,
              icon: const Icon(Icons.diamond),
              label: Text(l.refillWithGems(cost)),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => Navigator.pop(context, _OutOfHeartsChoice.practice),
              icon: const Icon(Icons.fitness_center),
              label: Text(l.practiceToEarnHeart),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _busy ? null : _plus, child: Text(l.getPlus)),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.quit)),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final code = error is AppException ? (error as AppException).error : null;
    return Scaffold(
      appBar: AppBar(leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(code == AppError.outOfHearts ? Icons.heart_broken : Icons.error_outline, size: 56, color: AppColors.red),
            const SizedBox(height: 16),
            Text(errorMessage(l, error), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            if (code == AppError.outOfHearts) ...[
              FilledButton.icon(
                onPressed: () => context.pushReplacement('/practice'),
                icon: const Icon(Icons.fitness_center),
                label: Text(l.practiceToEarnHeart),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: () => context.pushReplacement('/plus'), child: Text(l.getPlus)),
            ] else if (code == AppError.premiumRequired)
              FilledButton(onPressed: () => context.pushReplacement('/plus'), child: Text(l.getPlus))
            else if (code != AppError.lessonLocked && code != AppError.lessonNotFound && code != AppError.nothingToPractice)
              FilledButton(onPressed: onRetry, child: Text(l.retry)),
            TextButton(onPressed: () => context.pop(), child: Text(l.close)),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result, required this.practice});

  final LessonResult result;
  final bool practice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final achievements = ref.watch(achievementsProvider).value ?? const <Achievement>[];
    final unlocked = achievements.where((a) => result.newAchievements.contains(a.id)).toList();

    final (icon, title, body) = switch (result.status) {
      'completed' => (practice ? Icons.fitness_center : Icons.emoji_events, practice ? l.practiceComplete : l.lessonComplete, null),
      'failed' => (Icons.heart_broken, l.lessonFailed, l.lessonFailedBody),
      _ => (Icons.timer_off, l.lessonFailed, l.lessonExpired),
    };

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(icon, size: 96, color: result.completed ? AppColors.yellow : AppColors.red),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            ],
            if (result.completed) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(Icons.star_rounded, size: 44, color: i < result.stars ? AppColors.yellow : AppColors.border),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: StatTile(icon: Icons.bolt, color: AppColors.yellow, value: '+${result.xpAwarded}', label: l.xpEarned)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.monetization_on,
                      color: AppColors.green,
                      value: '+${formatEur(result.coinsAwarded, locale: locale, decimals: 0)}',
                      label: l.cashEarned,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.track_changes,
                      color: AppColors.blue,
                      value: '${result.total == 0 ? 100 : (result.correct * 100 / result.total).round()}%',
                      label: l.accuracy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (result.heartAwarded) _Banner(icon: Icons.favorite, color: AppColors.red, text: l.heartRecovered),
              if (result.streakExtendedToday)
                _Banner(icon: Icons.local_fire_department, color: AppColors.orange, text: l.streakExtended(result.streak)),
              if (result.leveledUp) _Banner(icon: Icons.rocket_launch, color: AppColors.purple, text: l.levelUp(result.level)),
              for (final a in unlocked) _Banner(icon: iconFor(a.icon), color: AppColors.pink, text: '${l.newAchievement} ${a.title}'),
              if (!result.firstCompletion && !practice)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.replayNote, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                ),
            ],
            const SizedBox(height: 32),
            FilledButton(onPressed: () => context.pop(), child: Text(l.done)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
