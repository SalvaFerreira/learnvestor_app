import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'router.dart';

class LearnVestorApp extends ConsumerWidget {
  const LearnVestorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileLocale = ref.watch(playerStateProvider).value?.profile.locale;
    return MaterialApp.router(
      title: 'LearnVestor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
      locale: profileLocale == null ? null : Locale(profileLocale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    );
  }
}

/// Shown when the build was made without Supabase configuration.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(AppLocalizations.of(context).authNotConfigured, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
