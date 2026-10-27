import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../data/repository.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider = Provider<Repository>((ref) => Repository(ref.watch(supabaseProvider)));

final _authEventsProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// Id of this device's anonymous user (there are no logins). Only changes when the
/// session is created or removed (not on token refresh), so everything keyed on it
/// reloads exactly when the user changes.
final userIdProvider = Provider<String?>((ref) {
  ref.watch(_authEventsProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

final playerStateProvider = FutureProvider<PlayerState?>((ref) async {
  final uid = ref.watch(userIdProvider);
  if (uid == null) return null;
  return ref.watch(repositoryProvider).getState();
});

/// UI and content language: the profile's choice once it exists, otherwise the device's.
final contentLocaleProvider = Provider<String>((ref) {
  final fromProfile = ref.watch(playerStateProvider).value?.profile.locale;
  if (fromProfile != null) return fromProfile;
  final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return device == 'pt' ? 'pt' : 'en';
});

final learningPathProvider = FutureProvider<List<Track>>((ref) async {
  if (ref.watch(userIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).getLearningPath(ref.watch(contentLocaleProvider));
});

final portfolioProvider = FutureProvider<Portfolio>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repositoryProvider).getPortfolio();
});

final instrumentsProvider = FutureProvider<List<Instrument>>((ref) => ref.watch(repositoryProvider).getInstruments());

final quotesProvider = FutureProvider<Map<String, Quote>>((ref) => ref.watch(repositoryProvider).getQuotes());

final fxRatesProvider = FutureProvider<Map<String, double>>((ref) => ref.watch(repositoryProvider).getFxRates());

final achievementsProvider = FutureProvider<List<Achievement>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(repositoryProvider).getAchievements(ref.watch(contentLocaleProvider));
});

/// Reload everything a finished lesson can change.
void refreshAfterLesson(WidgetRef ref) {
  ref
    ..invalidate(playerStateProvider)
    ..invalidate(learningPathProvider)
    ..invalidate(achievementsProvider);
}

/// Reload everything a trade can change.
void refreshAfterTrade(WidgetRef ref) {
  ref
    ..invalidate(playerStateProvider)
    ..invalidate(portfolioProvider)
    ..invalidate(achievementsProvider);
}
