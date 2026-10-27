/// Build-time configuration, passed with --dart-define (see apps/mobile/README.md).
abstract final class AppConfig {
  /// Browser demo (tools/web-demo): the whole backend runs inside the page.
  static const demo = bool.fromEnvironment('DEMO');

  /// Development only: the local demo API served by tools/db-tests/dev-server.mjs.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const privacyUrl = 'https://salvaferreira.github.io/LearnVestor_Website/privacy.html';
  static const termsUrl = 'https://salvaferreira.github.io/LearnVestor_Website/terms.html';
  static const disclaimerUrl = 'https://salvaferreira.github.io/LearnVestor_Website/disclaimer.html';
  static const feedbackUrl = 'https://salvaferreira.github.io/LearnVestor_Website/?from=demo#feedback';

  static bool get isConfigured => demo || (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty);
}
