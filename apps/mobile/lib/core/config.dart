/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md).
/// Only public values belong here: the Supabase publishable (anon) key and RevenueCat
/// public SDK keys are designed to ship inside the app. Never put secret/service-role
/// keys in the app.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const revenueCatAppleKey = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const revenueCatGoogleKey = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const environment = String.fromEnvironment('APP_ENV', defaultValue: 'development');

  /// Version of the terms the user accepts during onboarding (stored with the consent).
  static const termsVersion = '2025-09-15';

  static const privacyUrl = 'https://salvaferreira.github.io/LearnVestor/privacy.html';
  static const termsUrl = 'https://salvaferreira.github.io/LearnVestor/terms.html';
  static const disclaimerUrl = 'https://salvaferreira.github.io/LearnVestor/disclaimer.html';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
