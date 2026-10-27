import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OtpType;

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

/// Passwordless sign-in: email → 6-digit code. Works on every platform without deep links.
/// (Sign in with Apple / Google can be added on top; Apple requires its button whenever
/// another social login is offered on iOS.)
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = context.l10n.invalidEmail);
      return;
    }
    await _run(() async {
      final timezone = await FlutterTimezone.getLocalTimezone().then((t) => t.identifier).catchError((_) => 'UTC');
      await ref.read(supabaseProvider).auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        // Read once by the signup trigger to initialise the profile.
        data: {'locale': ref.read(contentLocaleProvider), 'timezone': timezone},
      );
      setState(() => _codeSent = true);
    });
  }

  Future<void> _verify() async {
    await _run(() => ref.read(supabaseProvider).auth.verifyOTP(
          email: _email.text.trim().toLowerCase(),
          token: _code.text.trim(),
          type: OtpType.email,
        ));
    // The router redirects once the session exists.
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/logo.png', height: 72),
                  const SizedBox(height: 16),
                  Text(l.appName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(l.signInTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                  const SizedBox(height: 40),
                  if (!_codeSent) ...[
                    Text(l.signInSubtitle, style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: l.emailLabel, prefixIcon: const Icon(Icons.mail_outline)),
                      onSubmitted: (_) => _sendCode(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _busy ? null : _sendCode, child: Text(l.sendCode)),
                  ] else ...[
                    Text(l.codeSentTo(_email.text.trim()), style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(labelText: l.codeLabel, counterText: ''),
                      onSubmitted: (_) => _verify(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _busy ? null : _verify, child: Text(l.verify)),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _codeSent = false),
                      child: Text(l.changeEmail),
                    ),
                  ],
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
