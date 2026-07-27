import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';
import 'supabase_profile_repository.dart';

/// The real `profiles` row — every profile in the app, member or admin-viewed.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => const SupabaseProfileRepository(),
);

/// Any profile, by id: the feed byline, another member's profile, the follow
/// lists. Real rows, real ids — there is no seeded person left to resolve.
final profileProvider = FutureProvider.family<UserProfile, String>(
  (ref, id) => ref.watch(profileRepositoryProvider).profileById(id),
);

/// The signed-in person's profile.
final currentProfileProvider = FutureProvider<UserProfile>((ref) async {
  final id = ref.watch(currentAuthUserIdProvider);
  if (id == null) {
    throw StateError('currentProfileProvider read while signed out');
  }
  return ref.watch(profileRepositoryProvider).profileById(id);
});
