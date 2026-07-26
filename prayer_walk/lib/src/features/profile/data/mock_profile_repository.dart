import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

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

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => MockProfileRepository(ref.watch(mockBackendProvider)),
);

/// Any profile, by id.
final profileProvider = FutureProvider.family<UserProfile, String>(
  (ref, id) => ref.watch(profileRepositoryProvider).profileById(id),
);

/// The signed-in person's profile.
///
/// PHASE-2 BRIDGE: real identity — display name and role — comes from the
/// Supabase `profiles` row ([authProfileProvider]); the rich stats, handle and
/// walk history are still the seeded dataset keyed to [currentUserIdProvider].
/// The screen therefore shows the *real* signed-in name and the *real* role
/// over Phase 1's mock history, until the content backend is migrated too.
final currentProfileProvider = FutureProvider<UserProfile>((ref) async {
  final id = ref.watch(currentUserIdProvider);
  if (id == null) {
    throw StateError('currentProfileProvider read while signed out');
  }
  final seeded = await ref.watch(profileRepositoryProvider).profileById(id);
  final account = await ref.watch(authProfileProvider.future);
  if (account == null) return seeded;
  final realName = account.fullName?.trim();
  return seeded.copyWith(
    displayName: (realName != null && realName.isNotEmpty)
        ? realName
        : seeded.displayName,
    role: account.role,
  );
});
