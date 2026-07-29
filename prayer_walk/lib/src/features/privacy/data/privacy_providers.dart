import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/activity_visibility.dart';
import '../domain/privacy_repository.dart';
import '../domain/privacy_zone.dart';
import 'supabase_privacy_repository.dart';

/// Visibility, zones and blocks for whoever is signed in.
///
/// Rebuilt on a session change, like the activity repository, because every
/// method here is about one account and reading them as somebody else would be
/// meaningless rather than merely wrong.
final privacyRepositoryProvider = Provider<PrivacyRepository>(
  (ref) => SupabasePrivacyRepository(ref.watch(currentAuthUserIdProvider)),
);

/// What a new walk starts as. Read once by the summary screen so the picker
/// opens on the member's own standing choice rather than on the app's.
final defaultVisibilityProvider = FutureProvider<ActivityVisibility>(
  (ref) => ref.watch(privacyRepositoryProvider).defaultVisibility(),
);

/// Whether the one-time explanation of a public walk has been shown. Watched by
/// the visibility picker, which is the only place it can be triggered.
final publicWalkNoticeSeenProvider = FutureProvider<bool>(
  (ref) => ref.watch(privacyRepositoryProvider).publicWalkNoticeSeen(),
);

/// The signed-in member's privacy zones. There is no family variant, and there
/// is not going to be: nobody may read anybody else's.
final privacyZonesProvider = FutureProvider<List<PrivacyZone>>(
  (ref) => ref.watch(privacyRepositoryProvider).zones(),
);

final blockedMembersProvider = FutureProvider<List<UserProfile>>(
  (ref) => ref.watch(privacyRepositoryProvider).blockedMembers(),
);

/// Whether the signed-in person has blocked [otherId]. False for yourself.
final isBlockedProvider = FutureProvider.family<bool, String>((ref, otherId) {
  final viewerId = ref.watch(currentAuthUserIdProvider);
  if (viewerId == null || viewerId == otherId) return Future.value(false);
  return ref.watch(privacyRepositoryProvider).isBlocked(otherId);
});
