import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../ui/common.dart';

final _offeringsProvider = FutureProvider.autoDispose<Offerings?>((ref) => ref.watch(purchasesProvider).offerings());

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _busy = false;

  Future<void> _buy(Package package, {required bool subscription}) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final completed = await ref.read(purchasesProvider).purchase(package);
      if (!completed) return;
      if (subscription && mounted) showMessage(context, l.activatingPlus);
      // The webhook updates the database a moment after the store confirms the purchase.
      for (var attempt = 0; attempt < 5; attempt++) {
        ref.invalidate(playerStateProvider);
        final state = await ref.read(playerStateProvider.future);
        if (!subscription || (state?.isPlus ?? false)) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (_) {
      if (mounted) showMessage(context, l.purchaseFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final player = ref.watch(playerStateProvider).value;
    final purchases = ref.watch(purchasesProvider);

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(28)),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium, size: 64, color: Colors.white),
                const SizedBox(height: 8),
                Text(l.plusTitle, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(l.plusHeadline, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final (icon, text) in [
            (Icons.favorite, l.plusBenefitHearts),
            (Icons.insights, l.plusBenefitAdvanced),
            (Icons.volunteer_activism, l.plusBenefitSupport),
          ])
            ListTile(leading: Icon(icon, color: AppColors.pink), title: Text(text), contentPadding: EdgeInsets.zero),
          const SizedBox(height: 16),
          if (player?.isPlus ?? false)
            SectionCard(child: Text(l.plusActive, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))
          else if (!purchases.isSupported)
            SectionCard(child: Text(l.purchasesUnavailable, textAlign: TextAlign.center))
          else
            AsyncBody(
              value: ref.watch(_offeringsProvider),
              onRetry: () => ref.invalidate(_offeringsProvider),
              builder: (offerings) {
                final plans = offerings?.current?.availablePackages ?? const <Package>[];
                final gems = offerings?.getOffering('gems')?.availablePackages ?? const <Package>[];
                if (plans.isEmpty && gems.isEmpty) return Text(l.noOffers, textAlign: TextAlign.center);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in plans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FilledButton(
                          onPressed: _busy ? null : () => _buy(p, subscription: true),
                          child: Text('${p.storeProduct.title} · ${p.storeProduct.priceString}'),
                        ),
                      ),
                    if (gems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(l.gemPacks, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      for (final p in gems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _buy(p, subscription: false),
                            icon: const Icon(Icons.diamond, color: AppColors.blue),
                            label: Text('${p.storeProduct.title} · ${p.storeProduct.priceString}'),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          const SizedBox(height: 16),
          Text(l.subscriptionTerms, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
