import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../ui/common.dart';

/// Bottom navigation + the top bar shared by the five main tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    _syncAccount();
  }

  /// Once per session: link purchases to the account and keep the profile's time zone
  /// (used for streak days) in line with the device.
  Future<void> _syncAccount() async {
    final player = await ref.read(playerStateProvider.future);
    if (player == null) return;
    await ref.read(purchasesProvider).identify(player.profile.id).catchError((_) {});
    try {
      final tz = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (tz != player.profile.timezone) {
        await ref.read(repositoryProvider).updateProfile({'timezone': tz});
        ref.invalidate(playerStateProvider);
      }
    } catch (_) {
      // Throttled (once per day) or unsupported platform: the server keeps the old zone.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: l.navHome),
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: l.navLearn),
          NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore), label: l.navExplore),
          NavigationDestination(icon: const Icon(Icons.pie_chart_outline), selectedIcon: const Icon(Icons.pie_chart), label: l.navPortfolio),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: l.navProfile),
        ],
      ),
    );
  }
}

/// Logo, hearts and gems, as in the mockups.
class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopBar({super.key, this.title});

  final String? title;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerStateProvider).value;
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 20,
      title: Row(
        children: [
          Image.asset('assets/logo.png', height: 32),
          const SizedBox(width: 10),
          Text(title ?? context.l10n.appName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
        ],
      ),
      actions: [
        if (player != null) ...[
          GemsBadge(gems: player.stats.gems),
          const SizedBox(width: 14),
          HeartsBadge(hearts: player.stats.hearts, maxHearts: player.stats.maxHearts, unlimited: player.isPlus),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.plusTitle,
            onPressed: () => context.push('/plus'),
            icon: const CircleAvatar(
              backgroundColor: Color(0x33F97316),
              child: Icon(Icons.rocket_launch, color: AppColors.orange),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}
