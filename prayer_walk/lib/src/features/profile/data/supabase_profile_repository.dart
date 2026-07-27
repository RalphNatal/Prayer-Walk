import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';
import 'profile_row_mapper.dart';

/// A profile problem worth showing the person, phrased in the app's voice.
///
/// Mirrors `AuthFailure`: anything thrown as a [ProfileFailure] is safe — and
/// intended — to show inline. Everything else stays a raw exception and gets
/// the generic "that didn't save" copy.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The real `profiles` row, read and written through RLS.
///
/// This is the template the remaining de-mocks copy: the screens keep talking
/// to providers, the providers talk to a [ProfileRepository], and only this
/// file knows there is a Supabase client at all.
///
/// Lifetime stats and the follow counts are no longer placeholders — they come
/// from `member_stats`, which derives them from the real rows in one query.
/// [UserProfile.accentIndex] still has no column by design: it is derived from
/// the id so the avatar tint is stable without storing it.
class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository();

  @override
  Future<UserProfile> profileById(String id) async {
    // Fired together rather than awaited in turn: the row and its totals are
    // independent, and a profile should cost one wait, not two.
    final results = await Future.wait<dynamic>([
      supabase.from('profiles').select(profileColumns).eq('id', id).single(),
      supabase.rpc('member_stats', params: {'target': id}),
    ]);

    return _merge(
      results[0] as Map<String, dynamic>,
      results[1] as List<dynamic>,
    );
  }

  @override
  Future<UserProfile> updateProfile(String id, ProfileEdit edit) async {
    try {
      await supabase
          .from('profiles')
          .update({
            'full_name': edit.displayName.trim(),
            'handle': normaliseHandle(edit.handle),
            'bio': edit.bio.trim(),
            'parish': edit.parish.trim(),
          })
          .eq('id', id);
    } on PostgrestException catch (error) {
      // 23505 = unique_violation. `handle` is the only unique column the app
      // writes, so this can only be a collision on it.
      if (error.code == '23505') {
        throw const ProfileFailure("That handle's taken — try another.");
      }
      rethrow;
    }
    // Read back through the same path as everything else, so the profile the
    // edit screen hands on carries its stats and counts like any other.
    return profileById(id);
  }

  /// Joins a `profiles` row to its `member_stats` row. An absent stats row —
  /// which should not happen, but is cheap to survive — leaves the honest
  /// zeros in place rather than failing the whole profile.
  UserProfile _merge(Map<String, dynamic> row, List<dynamic> statsRows) {
    final stats = statsRows.isEmpty
        ? null
        : statsRows.first as Map<String, dynamic>;

    return userProfileFromRow(
      row,
      stats: lifetimeStatsFromRow(stats),
      followerCount: (stats?['follower_count'] as num?)?.toInt() ?? 0,
      followingCount: (stats?['following_count'] as num?)?.toInt() ?? 0,
    );
  }
}
