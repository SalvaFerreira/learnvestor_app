import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/shell.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const TopBar(),
      body: AsyncBody(
        value: ref.watch(playerStateProvider),
        onRetry: () => ref.invalidate(playerStateProvider),
        builder: (player) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(playerStateProvider)
              ..invalidate(achievementsProvider);
            await ref.read(playerStateProvider.future);
          },
          child: _HomeContent(player: player!),
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = player.stats;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _LevelCard(level: s.level),
        const SizedBox(height: 20),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(l.experienceProgress, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  Text(l.xpCount(s.xp), style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: s.levelProgress,
                  minHeight: 12,
                  backgroundColor: AppColors.surfaceHigh,
                  color: AppColors.yellow,
                ),
              ),
              const SizedBox(height: 10),
              Text(l.xpToLevel(s.xpToNextLevel, s.level + 1), style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Text(l.dailyGoalProgress(s.xpToday, player.profile.dailyGoalXp), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (s.xpToday / player.profile.dailyGoalXp).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceHigh,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _StreakCard(stats: s),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(
                icon: Icons.trending_up,
                color: AppColors.green,
                value: formatEur(player.totalValue, locale: locale, decimals: 0),
                label: l.portfolioValue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(icon: Icons.school, color: AppColors.blue, value: '${s.lessonsCompleted}', label: l.lessonsDone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                icon: Icons.monetization_on,
                color: AppColors.yellow,
                value: formatEur(s.coinsEarned, locale: locale, decimals: 0),
                label: l.totalEarned,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _continueLearning(context, ref),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l.continueLearning),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: const Icon(Icons.calculate, color: AppColors.blue, size: 32),
            title: Text(l.toolsTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(l.toolsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/tools'),
          ),
        ),
        const SizedBox(height: 28),
        Text('${l.yourAchievements} 🏆', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _AchievementsStrip(),
        const SizedBox(height: 28),
        const _DemoCard(),
      ],
    );
  }

  Future<void> _continueLearning(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(learningPathProvider.future);
    final next = path.expand((t) => t.lessons).where((l) => l.status == LessonStatus.unlocked).firstOrNull;
    if (!context.mounted) return;
    if (next == null) {
      context.go('/learn');
    } else {
      context.push('/lesson/${next.id}');
    }
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.pink, AppColors.purple]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌱', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Text(l.levelLabel(level), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                    child: Text(rankTitle(l, level), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('${l.homeTagline} 🎯', style: const TextStyle(fontSize: 17)),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final message = stats.streakExtendedToday
        ? l.streakDoneToday
        : stats.streak > 0
            ? l.streakPending
            : l.streakStart;
    return SectionCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🔥', style: TextStyle(fontSize: 44, color: stats.streak > 0 ? null : Colors.grey)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.streakDays(stats.streak), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text(l.longestStreak(stats.streakLongest), style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.pink, fontStyle: FontStyle.italic, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _AchievementsStrip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider).value ?? const <Achievement>[];
    final shown = [...achievements.where((a) => a.unlocked), ...achievements.where((a) => !a.unlocked)];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => AchievementBadge(achievement: shown[i]),
      ),
    );
  }
}

class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.achievement, this.width = 96});

  final Achievement achievement;
  final double width;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    return Tooltip(
      message: a.description,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: a.unlocked ? AppColors.brandGradient : null,
                color: a.unlocked ? null : AppColors.surfaceHigh,
              ),
              child: Icon(iconFor(a.icon), color: a.unlocked ? Colors.white : AppColors.textSecondary, size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              a.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: a.unlocked ? AppColors.textPrimary : AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Demo controls: start over, send feedback, and the educational notice with the legal pages.
class _DemoCard extends ConsumerWidget {
  const _DemoCard();

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.resetProgress),
        content: Text(l.resetProgressBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.resetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(repositoryProvider).deleteAccount();
      // Back to the start screen, which creates a fresh learner with full hearts.
      await ref.read(supabaseProvider).auth.signOut();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.demoTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(l.demoBody, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(AppConfig.feedbackUrl)),
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(l.sendFeedback),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => _reset(context, ref),
            icon: const Icon(Icons.restart_alt),
            label: Text(l.resetProgress),
          ),
          const SizedBox(height: 16),
          Text(l.educationalNotice, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              for (final (label, url) in [
                (l.privacyPolicy, AppConfig.privacyUrl),
                (l.termsOfService, AppConfig.termsUrl),
                (l.investmentDisclaimer, AppConfig.disclaimerUrl),
              ])
                TextButton(onPressed: () => launchUrl(Uri.parse(url)), child: Text(label, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ],
      ),
    );
  }
}
