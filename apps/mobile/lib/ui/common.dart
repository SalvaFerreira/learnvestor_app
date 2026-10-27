import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

String errorMessage(AppLocalizations l, Object error) {
  if (error is AuthException) return l.invalidCode;
  if (error is! AppException) {
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('ClientException') || text.contains('Failed host lookup')) {
      return l.errorNetwork;
    }
    return l.errorGeneric;
  }
  return switch (error.error) {
    AppError.lessonLocked => l.errorLessonLocked,
    AppError.lessonNotFound => l.errorLessonNotFound,
    AppError.premiumRequired => l.errorPremiumRequired,
    AppError.outOfHearts => l.errorOutOfHearts,
    AppError.tooFast => l.errorTooFast,
    AppError.rateLimited => l.errorRateLimited,
    AppError.attemptClosed => l.errorAttemptClosed,
    AppError.insufficientGems => l.errorInsufficientGems,
    AppError.heartsFull => l.errorHeartsFull,
    AppError.maxStreakFreezes => l.errorMaxStreakFreezes,
    AppError.insufficientCash => l.errorInsufficientCash,
    AppError.insufficientShares => l.errorInsufficientShares,
    AppError.amountTooSmall => l.errorAmountTooSmall,
    AppError.quoteUnavailable => l.errorQuoteUnavailable,
    AppError.usernameTaken => l.errorUsernameTaken,
    AppError.usernameNotAllowed => l.errorUsernameNotAllowed,
    AppError.nothingToPractice => l.errorNothingToPractice,
    AppError.invalidProfile => l.errorInvalidProfile,
    AppError.timezoneChangeTooSoon => l.errorTimezone,
    AppError.network => l.errorNetwork,
    AppError.notAuthenticated || AppError.unknown => l.errorGeneric,
  };
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(errorMessage(context.l10n, error)), backgroundColor: AppColors.red),
  );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String rankTitle(AppLocalizations l, int level) => switch (level) {
      <= 2 => l.rankBeginner,
      <= 5 => l.rankApprentice,
      <= 9 => l.rankSkilled,
      _ => l.rankExpert,
    };

/// Content refers to Material icons by name (tracks, achievements).
IconData iconFor(String name) => switch (name) {
      'account_balance' => Icons.account_balance,
      'trending_up' => Icons.trending_up,
      'insights' => Icons.insights,
      'receipt_long' => Icons.receipt_long,
      'psychology' => Icons.psychology,
      'school' => Icons.school,
      'menu_book' => Icons.menu_book,
      'workspace_premium' => Icons.workspace_premium,
      'local_fire_department' => Icons.local_fire_department,
      'whatshot' => Icons.whatshot,
      'military_tech' => Icons.military_tech,
      'rocket_launch' => Icons.rocket_launch,
      'bolt' => Icons.bolt,
      'show_chart' => Icons.show_chart,
      'swap_horiz' => Icons.swap_horiz,
      'pie_chart' => Icons.pie_chart,
      _ => Icons.star,
    };

Color hexColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));

/// Loading / error / data switch with a retry button.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, required this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(errorMessage(context.l10n, error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
            ],
          ),
        ),
      ),
    );
  }
}

class HeartsBadge extends StatelessWidget {
  const HeartsBadge({super.key, required this.hearts, required this.maxHearts, this.unlimited = false});

  factory HeartsBadge.fromInfo(HeartsInfo info) =>
      HeartsBadge(hearts: info.hearts, maxHearts: info.maxHearts, unlimited: info.unlimited);

  final int hearts;
  final int maxHearts;
  final bool unlimited;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite, color: AppColors.red, size: 22),
        const SizedBox(width: 4),
        Text(unlimited ? '∞' : '$hearts/$maxHearts', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }
}

class GemsBadge extends StatelessWidget {
  const GemsBadge({super.key, required this.gems});

  final int gems;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.diamond, color: AppColors.blue, size: 20),
        const SizedBox(width: 4),
        Text('$gems', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Company logo, falling back to the ticker's initials.
class InstrumentAvatar extends StatelessWidget {
  const InstrumentAvatar({super.key, required this.symbol, this.logoUrl, this.size = 48});

  final String symbol;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ticker = symbol.split('.').first;
    final fallback = Center(
      child: Text(
        ticker.length > 2 ? ticker.substring(0, 2) : ticker,
        style: TextStyle(color: AppColors.background, fontWeight: FontWeight.w800, fontSize: size * 0.32),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.25)),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.12),
      child: logoUrl == null
          ? fallback
          : Image.network(logoUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class PlusBadge extends StatelessWidget {
  const PlusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(8)),
      child: Text(context.l10n.plusBadge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
