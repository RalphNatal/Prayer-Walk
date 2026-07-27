import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../profile/data/profile_row_mapper.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/social.dart';
import '../domain/social_repository.dart';

/// A social problem worth showing the person, phrased in the app's voice.
///
/// Same contract as `ProfileFailure`: a [SocialFailure] is safe to show inline;
/// anything else stays a raw exception and gets the generic copy.
class SocialFailure implements Exception {
  const SocialFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The follow graph, encouragements and comments, through RLS.
///
/// Both toggles are read-then-write rather than an upsert, because the answer
/// the caller needs is *which way it went*. The unique constraint on
/// `(activity_id, from_user_id)` — and the primary key on `follows` — are what
/// make that safe when two taps race: the loser gets a 23505, which means the
/// row is already there, which is the state we were trying to reach.
class SupabaseSocialRepository implements SocialRepository {
  const SupabaseSocialRepository();

  /// The longest comment the `comments` check constraint will accept.
  static const _maxCommentLength = 2000;

  // -------------------------------------------------------------- comments ---

  @override
  Future<List<CommentWithAuthor>> commentsFor(String activityId) async {
    final rows = await supabase
        .from('comments')
        .select('id, activity_id, author_id, body, created_at, '
            'author:profiles($profileColumns)')
        .eq('activity_id', activityId)
        .order('created_at', ascending: true);

    return [
      for (final row in rows)
        CommentWithAuthor(
          comment: Comment(
            id: row['id'] as String,
            activityId: row['activity_id'] as String,
            authorId: row['author_id'] as String,
            body: (row['body'] as String?) ?? '',
            createdAt:
                DateTime.tryParse((row['created_at'] as String?) ?? '')
                    ?.toLocal() ??
                DateTime.now(),
          ),
          author: userProfileFromRow(row['author'] as Map<String, dynamic>),
        ),
    ];
  }

  @override
  Future<void> addComment({
    required String activityId,
    required String authorId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const SocialFailure('Write something first.');
    }
    if (trimmed.length > _maxCommentLength) {
      throw const SocialFailure(
        "That's longer than a comment can be. Trim it and try again.",
      );
    }

    try {
      await supabase.from('comments').insert({
        'activity_id': activityId,
        'author_id': authorId,
        'body': trimmed,
      });
    } on PostgrestException catch (error) {
      // 23514 = check_violation. The only check on `comments` is the body
      // length, so the server disagreeing with the guard above can only mean
      // the same thing it does.
      if (error.code == '23514') {
        throw const SocialFailure(
          "That comment didn't fit — it has to be between 1 and "
          '$_maxCommentLength characters.',
        );
      }
      rethrow;
    }
  }

  // -------------------------------------------------------- encouragements ---

  @override
  Future<bool> toggleEncouragement({
    required String activityId,
    required String viewerId,
  }) async {
    final existing = await supabase
        .from('encouragements')
        .select('id')
        .eq('activity_id', activityId)
        .eq('from_user_id', viewerId)
        .maybeSingle();

    if (existing != null) {
      await supabase
          .from('encouragements')
          .delete()
          .eq('activity_id', activityId)
          .eq('from_user_id', viewerId);
      return false;
    }

    try {
      await supabase.from('encouragements').insert({
        'activity_id': activityId,
        'from_user_id': viewerId,
      });
    } on PostgrestException catch (error) {
      // Already encouraged — someone else's tap, or ours twice. Either way the
      // walk is encouraged, which is what the caller is being told.
      if (error.code != '23505') rethrow;
    }
    return true;
  }

  @override
  Future<List<UserProfile>> encouragedBy(String activityId) async {
    final rows = await supabase
        .from('encouragements')
        .select('profile:profiles($profileColumns)')
        .eq('activity_id', activityId)
        .order('created_at', ascending: true);

    return [
      for (final row in rows)
        userProfileFromRow(row['profile'] as Map<String, dynamic>),
    ];
  }

  // --------------------------------------------------------------- follows ---

  @override
  Future<List<UserProfile>> followers(String userId) async {
    // `follows` reaches `profiles` twice, so the embed names the constraint it
    // means. Without the hint PostgREST cannot tell follower from followee.
    final rows = await supabase
        .from('follows')
        .select('follower:profiles!follows_follower_id_fkey($profileColumns)')
        .eq('followee_id', userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        userProfileFromRow(row['follower'] as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<UserProfile>> following(String userId) async {
    final rows = await supabase
        .from('follows')
        .select('followee:profiles!follows_followee_id_fkey($profileColumns)')
        .eq('follower_id', userId)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        userProfileFromRow(row['followee'] as Map<String, dynamic>),
    ];
  }

  @override
  Future<bool> isFollowing({
    required String viewerId,
    required String otherId,
  }) async {
    final row = await supabase
        .from('follows')
        .select('follower_id')
        .eq('follower_id', viewerId)
        .eq('followee_id', otherId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<bool> toggleFollow({
    required String viewerId,
    required String otherId,
  }) async {
    // The `no_self_follow` check constraint is the real boundary; this is here
    // so a bug upstream surfaces as a sentence rather than a Postgres code.
    if (viewerId == otherId) {
      throw const SocialFailure("You can't follow yourself.");
    }

    if (await isFollowing(viewerId: viewerId, otherId: otherId)) {
      await supabase
          .from('follows')
          .delete()
          .eq('follower_id', viewerId)
          .eq('followee_id', otherId);
      return false;
    }

    try {
      await supabase.from('follows').insert({
        'follower_id': viewerId,
        'followee_id': otherId,
      });
    } on PostgrestException catch (error) {
      // 23505 on the primary key: already following, which is the state the
      // caller is being told about.
      if (error.code != '23505') rethrow;
    }
    return true;
  }
}
