import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';
import '../home/home_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.profileTitle, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)), toolbarHeight: 64),
      body: AsyncBody(
        value: ref.watch(playerStateProvider),
        onRetry: () => ref.invalidate(playerStateProvider),
        builder: (player) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(playerStateProvider)
              ..invalidate(achievementsProvider)
              ..invalidate(leaderboardProvider);
            await ref.read(playerStateProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              _Header(player: player!),
              const SizedBox(height: 20),
              _StatsGrid(stats: player.stats),
              const SizedBox(height: 28),
              Text(l.achievementsTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const _AchievementsGrid(),
              const SizedBox(height: 28),
              Text(l.leaderboardTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const _LeaderboardCard(),
              const SizedBox(height: 28),
              Text(l.settingsTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _Settings(player: player),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.player});

  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final name = player.profile.username ?? '';
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
          alignment: Alignment.center,
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('@$name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              Text('${l.levelLabel(player.stats.level)} · ${rankTitle(l, player.stats.level)}', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tiles = [
      StatTile(icon: Icons.bolt, color: AppColors.yellow, value: '${stats.xp}', label: l.statsXp),
      StatTile(icon: Icons.local_fire_department, color: AppColors.orange, value: '${stats.streakLongest}', label: l.statsStreak),
      StatTile(icon: Icons.school, color: AppColors.blue, value: '${stats.lessonsCompleted}', label: l.statsLessons),
      StatTile(icon: Icons.diamond, color: AppColors.blue, value: '${stats.gems}', label: l.statsGems),
    ];
    return Row(
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tile),
        ],
      ],
    );
  }
}

class _AchievementsGrid extends ConsumerWidget {
  const _AchievementsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(achievementsProvider),
      onRetry: () => ref.invalidate(achievementsProvider),
      builder: (achievements) => Wrap(
        spacing: 8,
        runSpacing: 16,
        children: [for (final a in achievements) AchievementBadge(achievement: a, width: 100)],
      ),
    );
  }
}

class _LeaderboardCard extends ConsumerWidget {
  const _LeaderboardCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AsyncBody(
        value: ref.watch(leaderboardProvider),
        onRetry: () => ref.invalidate(leaderboardProvider),
        builder: (board) {
          if (board.entries.isEmpty) {
            return Padding(padding: const EdgeInsets.all(16), child: Text(l.leaderboardEmpty, textAlign: TextAlign.center));
          }
          return Column(
            children: [
              for (final e in board.entries.take(10))
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: switch (e.rank) {
                      1 => AppColors.yellow,
                      2 => const Color(0xFFC0C4CC),
                      3 => const Color(0xFFCD7F32),
                      _ => AppColors.surfaceHigh,
                    },
                    child: Text('${e.rank}', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  title: Text('@${e.username}', style: TextStyle(fontWeight: e.isMe ? FontWeight.w800 : FontWeight.w500, color: e.isMe ? AppColors.pink : null)),
                  trailing: Text(l.xpCount(e.xp), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onLongPress: e.isMe ? null : () => _reportName(context, ref, e.username),
                ),
              if (board.myRank != null && board.myRank! > 10)
                Padding(padding: const EdgeInsets.all(12), child: Text(l.yourRank(board.myRank!), style: const TextStyle(color: AppColors.pink))),
            ],
          );
        },
      ),
    );
  }
}

/// Long-press on a leaderboard name: report it as inappropriate (3 reports hide it).
Future<void> _reportName(BuildContext context, WidgetRef ref, String username) async {
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.reportUsername),
      content: Text(l.reportUsernameConfirm(username)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.reportSend)),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(repositoryProvider).reportUsername(username);
    if (context.mounted) showMessage(context, l.reportThanks);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _Settings extends ConsumerWidget {
  const _Settings({required this.player});

  final PlayerState player;

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final economy = player.economy;

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: Text(l.language),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'pt', label: Text('PT'))],
            selected: {player.profile.locale},
            onSelectionChanged: (s) => _guard(context, () async {
              await repo.updateProfile({'locale': s.first});
              ref
                ..invalidate(playerStateProvider)
                ..invalidate(learningPathProvider)
                ..invalidate(achievementsProvider);
            }),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.ac_unit, color: AppColors.blue),
          title: Text(l.streakFreeze),
          subtitle: Text(l.streakFreezeBody(player.stats.streakFreezes)),
          trailing: TextButton(
            onPressed: player.stats.streakFreezes >= economy.maxStreakFreezes || player.stats.gems < economy.streakFreezeGemCost
                ? null
                : () => _guard(context, () async {
                      await repo.buyStreakFreeze();
                      ref.invalidate(playerStateProvider);
                    }),
            child: Text(l.buyForGems(economy.streakFreezeGemCost)),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download),
          title: Text(l.exportData),
          onTap: () => _guard(context, () async {
            final data = await repo.exportMyData();
            await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
            if (context.mounted) showMessage(context, l.exportDone);
          }),
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gavel),
          title: Text(l.legal),
        ),
        for (final (label, url) in [
          (l.privacyPolicy, AppConfig.privacyUrl),
          (l.termsOfService, AppConfig.termsUrl),
          (l.investmentDisclaimer, AppConfig.disclaimerUrl),
        ])
          ListTile(
            contentPadding: const EdgeInsets.only(left: 40),
            title: Text(label),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(Uri.parse(url)),
          ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.smartphone),
          title: Text(l.noAccountTitle),
          subtitle: Text(AppConfig.demo ? l.demoNoAccountBody : l.noAccountBody),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_forever, color: AppColors.red),
          title: Text(l.deleteAccount, style: const TextStyle(color: AppColors.red)),
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteAccount),
        content: Text(l.deleteAccountBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.deleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(context, () async {
      await ref.read(repositoryProvider).deleteAccount();
      // Back to the start screen, which creates a fresh anonymous user.
      await ref.read(supabaseProvider).auth.signOut();
    });
  }
}
