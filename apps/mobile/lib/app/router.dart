import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/learn/learn_screen.dart';
import '../features/learn/lesson_screen.dart';
import '../features/portfolio/portfolio_screen.dart';
import '../features/start/start_screen.dart';
import '../features/tools/tools_screen.dart';
import '../state/providers.dart';
import 'shell.dart';

/// Re-runs the router's redirect whenever the session or the player state changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(userIdProvider, (_, _) => notifyListeners())
      ..listen(playerStateProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (ref.read(userIdProvider) == null) return location == '/start' ? null : '/start';

      final player = ref.read(playerStateProvider);
      if (player.isLoading && !player.hasValue) return location == '/splash' ? null : '/splash';
      // No onboarding in the demo: straight to the main menu.
      if (const {'/start', '/splash'}.contains(location)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/start', builder: (_, _) => const StartScreen()),
      GoRoute(path: '/lesson/:id', builder: (_, state) => LessonScreen(lessonId: state.pathParameters['id']!)),
      GoRoute(path: '/practice', builder: (_, _) => const LessonScreen.practice()),
      GoRoute(path: '/tools', builder: (_, _) => const ToolsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/learn', builder: (_, _) => const LearnScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/portfolio', builder: (_, _) => const PortfolioScreen())]),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Image.asset('assets/logo.png', width: 96)),
      );
}
