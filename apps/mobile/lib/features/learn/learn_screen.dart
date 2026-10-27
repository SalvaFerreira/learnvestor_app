import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

class LearnScreen extends ConsumerStatefulWidget {
  const LearnScreen({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen> {
  String? _trackId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final player = ref.watch(playerStateProvider).value;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(l.learnTitle, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        actions: [
          if (player != null)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: HeartsBadge(hearts: player.stats.hearts, maxHearts: player.stats.maxHearts),
            ),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(learningPathProvider),
        onRetry: () => ref.invalidate(learningPathProvider),
        builder: (tracks) {
          if (tracks.isEmpty) return const SizedBox.shrink();
          final track = tracks.firstWhere((t) => t.id == _trackId, orElse: () => tracks.firstWhere(
                (t) => t.lessons.any((lesson) => lesson.status == LessonStatus.unlocked),
                orElse: () => tracks.first,
              ));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(learningPathProvider);
              await ref.read(learningPathProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                if (player != null) _ProfileHeader(player: player),
                if (player != null && player.stats.lessonsCompleted > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center, color: AppColors.pink),
                        title: Text(l.practice, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(l.practiceHint),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/practice'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _TrackChip(
                      track: tracks[i],
                      selected: tracks[i].id == track.id,
                      onTap: () => setState(() => _trackId = tracks[i].id),
                    ),
                  ),
                ),
                const Divider(height: 32),
                for (final unit in track.units) _UnitPath(track: track, unit: unit),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = player.stats;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0x33F97316),
                child: Icon(Icons.rocket_launch, color: AppColors.orange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rankTitle(l, s.level), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('🌱 ${l.levelLabel(s.level)}', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.bolt, color: AppColors.yellow),
              Text(l.xpCount(s.xp), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: s.levelProgress, minHeight: 6, color: AppColors.yellow),
                ),
              ),
              const SizedBox(width: 12),
              Text(l.xpToLevel(s.xpToNextLevel, s.level + 1), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({required this.track, required this.selected, required this.onTap});

  final Track track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(track.color);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12)] : null,
        ),
        child: Row(
          children: [
            Icon(iconFor(track.icon), color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(track.title, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Zig-zag path of lesson cards, as in the mockups.
class _UnitPath extends StatelessWidget {
  const _UnitPath({required this.track, required this.unit});

  final Track track;
  final UnitNode unit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final color = hexColor(track.color);
    final stars = unit.lessons.fold<int>(0, (sum, lesson) => sum + (lesson.stars ?? 0));
    final percent = unit.lessons.isEmpty
        ? 0
        : (unit.lessons.where((lesson) => lesson.status == LessonStatus.completed).length * 100 / unit.lessons.length).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(unit.title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(unit.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: l.percentComplete(percent), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            TextSpan(text: ' • ${l.starsProgress(stars, unit.lessons.length * 3)}', style: const TextStyle(color: AppColors.textSecondary)),
          ])),
          const SizedBox(height: 20),
          for (final (i, lesson) in unit.lessons.indexed) ...[
            Align(
              alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(widthFactor: 0.72, child: _LessonCard(lesson: lesson, color: color)),
            ),
            if (i < unit.lessons.length - 1)
              Align(
                alignment: i.isEven ? const Alignment(0.35, 0) : const Alignment(-0.35, 0),
                child: Container(
                  width: 4,
                  height: 36,
                  color: lesson.status == LessonStatus.completed ? color : AppColors.border,
                ),
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson, required this.color});

  final LessonNode lesson;
  final Color color;

  void _open(BuildContext context) {
    switch (lesson.status) {
      case LessonStatus.completed || LessonStatus.unlocked:
        context.push('/lesson/${lesson.id}');
      case LessonStatus.locked:
        showMessage(context, context.l10n.errorLessonLocked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final active = lesson.playable;
    final headerColor = active ? color : AppColors.textSecondary;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          boxShadow: lesson.status == LessonStatus.unlocked ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18)] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: headerColor,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                    child: Icon(
                      switch (lesson.status) {
                        LessonStatus.completed => Icons.check_rounded,
                        LessonStatus.unlocked => Icons.play_arrow_rounded,
                        LessonStatus.locked => Icons.lock,
                      },
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(lesson.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.description, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.bolt, color: AppColors.yellow, size: 20),
                      Text(l.xpReward(lesson.xpReward), style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (lesson.stars != null)
                        Row(children: [
                          for (var i = 0; i < 3; i++)
                            Icon(Icons.star_rounded, size: 18, color: i < lesson.stars! ? AppColors.yellow : AppColors.border),
                        ])
                      else ...[
                        const Icon(Icons.monetization_on, color: AppColors.green, size: 20),
                        const SizedBox(width: 4),
                        Text('+${formatEur(lesson.coinReward, locale: locale, decimals: 0)}',
                            style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
