import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';
import 'supabase_profile_repository.dart';

class MockProfileRepository implements ProfileRepository {
  MockProfileRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<UserProfile> profileById(String id) =>
      _backend.read(() => _backend.userById(id));

  @override
  Future<UserProfile> updateProfile(String id, ProfileEdit edit) {
    return _backend.write(() {
      final handle = edit.handle.startsWith('@')
          ? edit.handle
          : '@${edit.handle}';
      final updated = _backend.userById(id).copyWith(
        displayName: edit.displayName.trim(),
        handle: handle.trim(),
        bio: edit.bio.trim(),
        parish: edit.parish.trim(),
      );
      _backend.replaceUser(updated);
      return updated;
    });
  }
}

/// The real `profiles` row — the Profile feature's backend as of this step.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => const SupabaseProfileRepository(),
);

/// The seeded dataset, still backing the profiles that *other* features look
/// up by id. See [profileProvider].
final mockProfileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => MockProfileRepository(ref.watch(mockBackendProvider)),
);

/// Any profile, by id.
///
/// PHASE-2 BRIDGE: still the seeded dataset. Every caller of this family — the
/// feed byline, another member's profile, the follow lists, admin member
/// detail — is resolving a *mock* id (`u_maria`, `u_ben`, …) that has no row in
/// Supabase, because those features have not been de-mocked yet. It moves to
/// [profileRepositoryProvider] when they do.
final profileProvider = FutureProvider.family<UserProfile, String>(
  (ref, id) => ref.watch(mockProfileRepositoryProvider).profileById(id),
);

/// The signed-in person's profile — real, from Supabase, keyed to the real
/// auth user id rather than a seeded one.
final currentProfileProvider = FutureProvider<UserProfile>((ref) async {
  final id = ref.watch(currentAuthUserIdProvider);
  if (id == null) {
    throw StateError('currentProfileProvider read while signed out');
  }
  return ref.watch(profileRepositoryProvider).profileById(id);
});
