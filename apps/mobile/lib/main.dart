import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config.dart';
import 'services/demo_http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    // The demo answers every request in the browser; the URL only has to be well formed.
    url: AppConfig.demo ? 'https://demo.learnvestor.local' : AppConfig.supabaseUrl,
    publishableKey: AppConfig.demo ? 'demo' : AppConfig.supabasePublishableKey,
    httpClient: AppConfig.demo ? DemoHttpClient() : null,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  runApp(const ProviderScope(child: LearnVestorApp()));
}
