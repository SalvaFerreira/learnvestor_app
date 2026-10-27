/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md).
/// Only public values belong here: the Supabase publishable (anon) key is designed to
/// ship inside the app. Never put secret/service-role keys in the app.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const environment = String.fromEnvironment('APP_ENV', defaultValue: 'development');

  /// Browser demo (tools/web-demo): the whole backend runs inside the page, so no
  /// Supabase URL or key is needed.
  static const demo = bool.fromEnvironment('DEMO');

  /// Version of the terms the user accepts during onboarding (stored with the consent).
  static const termsVersion = '2026-10-27';

  static const privacyUrl = 'https://salvaferreira.github.io/LearnVestor_Website/privacy.html';
  static const termsUrl = 'https://salvaferreira.github.io/LearnVestor_Website/terms.html';
  static const disclaimerUrl = 'https://salvaferreira.github.io/LearnVestor_Website/disclaimer.html';
  static const feedbackUrl = 'https://salvaferreira.github.io/LearnVestor_Website/?from=demo#feedback';

  static bool get isConfigured => demo || (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty);
}
