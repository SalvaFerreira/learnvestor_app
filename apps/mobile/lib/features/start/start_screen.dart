import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

/// There are no logins: on first launch the app creates an anonymous Supabase user for
/// this device and goes straight to onboarding. This screen only shows while that
/// session is being created, or when it failed (e.g. offline) so the learner can retry.
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({super.key});

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final timezone = await FlutterTimezone.getLocalTimezone().then((t) => t.identifier).catchError((_) => 'UTC');
      await ref.read(supabaseProvider).auth.signInAnonymously(
        // Read once by the signup trigger to initialise the profile.
        data: {'locale': ref.read(contentLocaleProvider), 'timezone': timezone},
      );
      // The router redirects once the session exists.
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(context.l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/logo.png', height: 72),
                  const SizedBox(height: 16),
                  Text(l.appName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 32),
                  if (_error == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _start, child: Text(l.retry)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
