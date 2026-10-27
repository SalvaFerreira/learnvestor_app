import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/config.dart';

/// RevenueCat wrapper. The app never decides entitlements itself: after a purchase the
/// RevenueCat webhook updates the database, and the app re-reads get_my_state.
///
/// Offerings expected in the RevenueCat dashboard:
///   * current offering: Plus subscription packages (monthly / annual)
///   * offering "gems":  consumables gems_100, gems_500, gems_1200
class PurchasesService {
  bool _configured = false;

  String? get _apiKey {
    if (kIsWeb) return null;
    final key = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => AppConfig.revenueCatAppleKey,
      TargetPlatform.android => AppConfig.revenueCatGoogleKey,
      _ => '',
    };
    return key.isEmpty ? null : key;
  }

  /// False on the web and in builds without RevenueCat keys.
  bool get isSupported => _apiKey != null;

  /// Links purchases to the Supabase user id (the webhook relies on it).
  Future<void> identify(String userId) async {
    if (!isSupported) return;
    if (!_configured) {
      await Purchases.configure(PurchasesConfiguration(_apiKey!)..appUserID = userId);
      _configured = true;
    } else {
      await Purchases.logIn(userId);
    }
  }

  Future<void> reset() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } on PlatformException {
      // Already anonymous.
    }
  }

  Future<Offerings?> offerings() async => isSupported ? Purchases.getOfferings() : null;

  /// Returns false when the user cancelled; throws on real failures.
  Future<bool> purchase(Package package) async {
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  Future<void> restore() => Purchases.restorePurchases();
}
