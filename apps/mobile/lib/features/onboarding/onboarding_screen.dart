import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _under16 = 'under16';
  static const _ageBrackets = ['16-17', '18-24', '25-34', '35-44', '45-54', '55+'];
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  final _username = TextEditingController();
  final _termsLink = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(AppConfig.termsUrl));
  final _privacyLink = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(AppConfig.privacyUrl));
  String? _age;
  int _goal = 20;
  bool _terms = false;
  bool _marketing = false;
  bool _analytics = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _termsLink.dispose();
    _privacyLink.dispose();
    super.dispose();
  }

  bool get _valid =>
      _usernamePattern.hasMatch(_username.text.trim()) && _age != null && _age != _under16 && _terms;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final country = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
      await ref.read(repositoryProvider).completeOnboarding(
            username: _username.text.trim(),
            ageBracket: _age!,
            dailyGoalXp: _goal,
            countryCode: country,
            termsVersion: AppConfig.termsVersion,
            marketingOptIn: _marketing,
            analyticsOptIn: _analytics,
          );
      ref.invalidate(playerStateProvider); // router moves on to /home
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(context.l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final goals = {10: l.goalCasual, 20: l.goalRegular, 30: l.goalSerious, 50: l.goalIntense};
    return Scaffold(
      appBar: AppBar(title: Text(l.onboardingTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _username,
              decoration: InputDecoration(labelText: l.usernameLabel, helperText: l.usernameHint, prefixIcon: const Icon(Icons.alternate_email)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            Text(l.ageLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final age in [_under16, ..._ageBrackets])
                  ChoiceChip(
                    label: Text(age == _under16 ? l.ageUnder16 : age),
                    selected: _age == age,
                    onSelected: (_) => setState(() => _age = age),
                  ),
              ],
            ),
            if (_age == _under16)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.ageBlocked, style: const TextStyle(color: AppColors.yellow)),
              ),
            const SizedBox(height: 24),
            Text(l.dailyGoalLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: _goal,
              onChanged: (v) => setState(() => _goal = v!),
              child: Column(
                children: [
                  for (final MapEntry(key: xp, value: name) in goals.entries)
                    RadioListTile<int>(value: xp, title: Text(name), subtitle: Text(l.goalOption(xp)), contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text.rich(
                TextSpan(
                  text: '${l.acceptTerms} (',
                  children: [
                    _link(l.termsOfService, _termsLink),
                    const TextSpan(text: ' · '),
                    _link(l.privacyPolicy, _privacyLink),
                    const TextSpan(text: ')'),
                  ],
                ),
              ),
            ),
            CheckboxListTile(
              value: _marketing,
              onChanged: (v) => setState(() => _marketing = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.marketingOptIn),
            ),
            CheckboxListTile(
              value: _analytics,
              onChanged: (v) => setState(() => _analytics = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.analyticsOptIn),
            ),
            const SizedBox(height: 12),
            Text(l.educationalNotice, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: AppColors.red)),
              ),
            FilledButton(onPressed: _valid && !_busy ? _submit : null, child: Text(l.startLearning)),
          ],
        ),
      ),
    );
  }

  TextSpan _link(String text, GestureRecognizer recognizer) => TextSpan(
        text: text,
        style: const TextStyle(color: AppColors.pink, decoration: TextDecoration.underline),
        recognizer: recognizer,
      );
}
