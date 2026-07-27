import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile.dart';
import 'auth_repository.dart';


enum AuthPhase { loading, signedOut, signedIn }

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final authPhaseProvider = Provider<AuthPhase>((ref) {
  final state = ref.watch(authStateProvider);
  return state.when(
    data: (value) =>
        value.session != null ? AuthPhase.signedIn : AuthPhase.signedOut,
    loading: () => ref.read(authRepositoryProvider).currentSession != null
        ? AuthPhase.signedIn
        : AuthPhase.signedOut,
    error: (_, _) => AuthPhase.signedOut,
  );
});

final authProfileProvider = FutureProvider<Profile?>((ref) async {
  if (ref.watch(authPhaseProvider) != AuthPhase.signedIn) return null;
  final repo = ref.read(authRepositoryProvider);
  final userId = repo.currentUser?.id;
  if (userId == null) return null;
  return repo.fetchProfile(userId);
});

/// The signed-in person's role, or null until the profile resolves.
final currentRoleProvider = Provider((ref) {
  return ref.watch(authProfileProvider).value?.role;
});

/// The real signed-in user id, or null while signed out.
///
/// The one identity in the app. There used to be a second — a
/// `currentUserIdProvider` handing out a seeded id to whatever was still on
/// mock data — and it is gone: the feed, the social graph and the stats all key
/// off this one now.
final currentAuthUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authPhaseProvider) == AuthPhase.signedIn
      ? ref.watch(authRepositoryProvider).currentUser?.id
      : null;
});

/// Whether onboarding has been shown this run. In-memory by design — same as
/// Phase 1, it resets on a cold start, and there is no backend to persist a
/// "seen" flag against yet.
class OnboardingSeen extends Notifier<bool> {
  @override
  bool build() => false;

  void markSeen() => state = true;
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeen, bool>(
  OnboardingSeen.new,
);
