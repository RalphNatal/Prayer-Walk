import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/social_repository.dart';
import 'supabase_social_repository.dart';

/// The real follow graph, encouragements and comments.
final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => const SupabaseSocialRepository(),
);

final commentsProvider = FutureProvider.family<List<CommentWithAuthor>, String>(
  (ref, activityId) =>
      ref.watch(socialRepositoryProvider).commentsFor(activityId),
);

final encouragedByProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, activityId) =>
      ref.watch(socialRepositoryProvider).encouragedBy(activityId),
);

final followersProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, userId) => ref.watch(socialRepositoryProvider).followers(userId),
);

final followingProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, userId) => ref.watch(socialRepositoryProvider).following(userId),
);

/// Whether the signed-in person follows [otherId]. False for yourself — there
/// is no row to find, and the button that reads this is hidden anyway.
final isFollowingProvider = FutureProvider.family<bool, String>((ref, otherId) {
  final viewerId = ref.watch(currentAuthUserIdProvider);
  if (viewerId == null || viewerId == otherId) return Future.value(false);
  return ref
      .watch(socialRepositoryProvider)
      .isFollowing(viewerId: viewerId, otherId: otherId);
});
