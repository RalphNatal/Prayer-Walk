import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/social.dart';
import '../domain/social_repository.dart';

class MockSocialRepository implements SocialRepository {
  MockSocialRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<List<CommentWithAuthor>> commentsFor(String activityId) {
    return _backend.readList(() {
      final rows = _backend.comments
          .where((c) => c.activityId == activityId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return rows
          .map(
            (c) => CommentWithAuthor(
              comment: c,
              author: _backend.userById(c.authorId),
            ),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<void> addComment({
    required String activityId,
    required String authorId,
    required String body,
  }) {
    return _backend.write(() {
      _backend.comments.add(
        Comment(
          id: _backend.nextId('c'),
          activityId: activityId,
          authorId: authorId,
          body: body.trim(),
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<bool> toggleEncouragement({
    required String activityId,
    required String viewerId,
  }) {
    return _backend.write(() {
      final existing = _backend.encouragements.indexWhere(
        (e) => e.activityId == activityId && e.fromUserId == viewerId,
      );
      if (existing >= 0) {
        _backend.encouragements.removeAt(existing);
        return false;
      }
      _backend.encouragements.add(
        Encouragement(
          id: _backend.nextId('e'),
          activityId: activityId,
          fromUserId: viewerId,
          createdAt: DateTime.now(),
        ),
      );
      return true;
    });
  }

  @override
  Future<List<UserProfile>> encouragedBy(String activityId) {
    return _backend.readList(
      () => _backend.encouragements
          .where((e) => e.activityId == activityId)
          .map((e) => _backend.userById(e.fromUserId))
          .toList(growable: false),
    );
  }

  @override
  Future<List<UserProfile>> followers(String userId) {
    return _backend.readList(
      () => _backend.follows
          .where((f) => f.followeeId == userId)
          .map((f) => _backend.userById(f.followerId))
          .toList(growable: false),
    );
  }

  @override
  Future<List<UserProfile>> following(String userId) {
    return _backend.readList(
      () => _backend.follows
          .where((f) => f.followerId == userId)
          .map((f) => _backend.userById(f.followeeId))
          .toList(growable: false),
    );
  }

  @override
  Future<bool> isFollowing({required String viewerId, required String otherId}) {
    return _backend.read(
      () => _backend.follows.any(
        (f) => f.followerId == viewerId && f.followeeId == otherId,
      ),
    );
  }

  @override
  Future<bool> toggleFollow({
    required String viewerId,
    required String otherId,
  }) {
    return _backend.write(() {
      final index = _backend.follows.indexWhere(
        (f) => f.followerId == viewerId && f.followeeId == otherId,
      );
      final nowFollowing = index < 0;
      if (nowFollowing) {
        _backend.follows.add(
          Follow(followerId: viewerId, followeeId: otherId),
        );
      } else {
        _backend.follows.removeAt(index);
      }
      final other = _backend.userById(otherId);
      _backend.replaceUser(
        other.copyWith(
          followerCount: (other.followerCount + (nowFollowing ? 1 : -1))
              .clamp(0, 1 << 30),
        ),
      );
      return nowFollowing;
    });
  }
}

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => MockSocialRepository(ref.watch(mockBackendProvider)),
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

final isFollowingProvider = FutureProvider.family<bool, String>((ref, otherId) {
  final viewerId = ref.watch(currentUserIdProvider);
  if (viewerId == null) return Future.value(false);
  return ref
      .watch(socialRepositoryProvider)
      .isFollowing(viewerId: viewerId, otherId: otherId);
});
