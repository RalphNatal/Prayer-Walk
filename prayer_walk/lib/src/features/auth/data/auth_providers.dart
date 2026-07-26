import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/mock_backend/seed_data.dart';
import '../domain/profile.dart';
import 'auth_repository.dart';

/// Where the person stands with auth, reduced to the three cases the router
/// cares about. Kept as a small enum (rather than the raw [Session]) so tests
/// can override it without fabricating a Supabase session.
enum AuthPhase { loading, signedOut, signedIn }

/// The live Supabase auth stream. `supabase_flutter` restores the persisted
/// session before this replays `initialSession`, so a returning user is never
/// shown the sign-in screen on a cold start.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// Signed in, signed out, or still resolving — the thing the redirect reads.
///
/// While the stream is warming up we fall back to the client's synchronously
/// restored `currentSession`, which is already populated by the time
/// `Supabase.initialize` returns. That closes the one-frame gap that would
/// otherwise flash the login screen before the stream's first event.
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

/// The signed-in person's `profiles` row — identity and, crucially, role.
///
/// `null` while signed out. Loading/error surface through the [AsyncValue] so
/// the router can hold on a splash until the role is known, and the profile
/// screen can show a proper loading/error state.
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

/// The id the mock content layer (feed, activities, social) is keyed to.
///
/// PHASE-2 BRIDGE: authentication is real, but the app's *content* is still the
/// seeded dataset from Phase 1. So while a real session exists, the content
/// keeps resolving against the seeded profile; real identity and role come from
/// [authProfileProvider] instead. When the content backend is migrated, this
/// returns the real `currentUser!.id` and the bridge goes away.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authPhaseProvider) == AuthPhase.signedIn
      ? MockSeed.currentUserId
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
