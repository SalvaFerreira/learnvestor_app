import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  void run() => runApp(const ProviderScope(child: LearnVestorApp()));

  if (AppConfig.sentryDsn.isEmpty) {
    run();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options
        ..dsn = AppConfig.sentryDsn
        ..environment = AppConfig.environment
        ..sendDefaultPii = false
        ..tracesSampleRate = 0.1;
    },
    appRunner: run,
  );
}
