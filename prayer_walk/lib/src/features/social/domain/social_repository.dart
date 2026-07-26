import '../../profile/domain/user_profile.dart';
import 'social.dart';

/// A comment joined with its author, ready to render.
class CommentWithAuthor {
  const CommentWithAuthor({required this.comment, required this.author});

  final Comment comment;
  final UserProfile author;
}

abstract interface class SocialRepository {
  Future<List<CommentWithAuthor>> commentsFor(String activityId);

  Future<void> addComment({
    required String activityId,
    required String authorId,
    required String body,
  });

  /// Adds or withdraws an encouragement. Returns the new state for [viewerId].
  Future<bool> toggleEncouragement({
    required String activityId,
    required String viewerId,
  });

  Future<List<UserProfile>> encouragedBy(String activityId);

  Future<List<UserProfile>> followers(String userId);

  Future<List<UserProfile>> following(String userId);

  Future<bool> isFollowing({required String viewerId, required String otherId});

  /// Follows or unfollows. Returns whether [viewerId] now follows [otherId].
  Future<bool> toggleFollow({required String viewerId, required String otherId});
}
