import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/profile_fields.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';
import 'profile_row_mapper.dart';

/// The Storage bucket created by `20260731000000_avatar_storage.sql`.
const _avatarBucket = 'avatars';

/// Seeded from the platform's secure entropy source rather than the clock, so
/// an object key cannot be guessed from one that was seen. See [_uuid].
final _random = Random.secure();

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
            // Clamped to the same lengths the columns declare, so a pasted
            // paragraph lands as a short field rather than as a failed save.
            // `role` and `status` are absent, and this map is the reason the
            // app has never had cause to send them.
            'full_name': clampField(edit.displayName, ProfileLimits.displayName),
            'handle': canonicalHandle(edit.handle),
            'bio': clampField(edit.bio, ProfileLimits.bio),
            'parish': clampField(edit.parish, ProfileLimits.parish),
            'pronouns': clampField(edit.pronouns, ProfileLimits.pronouns),
            'location': clampField(edit.location, ProfileLimits.location),
            // Normalised through the same validator the form used, not stored
            // as typed: what goes in the column is what was actually checked.
            // An unusable link is stored as empty rather than rejected — the
            // form has already said so, and losing a name change over a typo in
            // an optional field would be the wrong trade.
            'links': profileLink(edit.links) ?? '',
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

  /// Writes the object first, re-points the row second, sweeps the old object
  /// last. The order is the whole design.
  ///
  /// If the upload fails, the row still names the previous photo and that photo
  /// is still there. If the row update fails, the new object is orphaned but
  /// the member's avatar is unchanged — a wasted 60 KB is a much better outcome
  /// than a profile pointing at nothing. Only once the row no longer refers to
  /// the old object is the old object removed, and that removal is allowed to
  /// fail quietly: by then the member's photo has already changed, and throwing
  /// would report a failure for something that succeeded.
  ///
  /// The key is `{user_id}/{uuid}.jpg` — the folder is what the storage
  /// policies check, and the uuid is what makes the URL unguessable and lets a
  /// replacement be a new object rather than a cache-busting argument on an old
  /// one.
  @override
  Future<UserProfile> uploadAvatar(String id, AvatarUpload upload) async {
    final previous = await _currentAvatarUrl(id);
    final key = '$id/${_uuid()}.jpg';

    await supabase.storage
        .from(_avatarBucket)
        .uploadBinary(
          key,
          upload.bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            // Asked for by the brief, and harmless here: the key carries a
            // fresh uuid every time, so this only matters for a retry landing
            // on the same key after a partial failure.
            upsert: true,
            // A year. The uuid in the key is what makes that safe — a new photo
            // is a new URL, so nothing downstream ever has to be told a cached
            // image went stale.
            cacheControl: '31536000',
          ),
        );

    final url = supabase.storage.from(_avatarBucket).getPublicUrl(key);
    await supabase.from('profiles').update({'avatar_url': url}).eq('id', id);

    await _sweep(previous);
    return profileById(id);
  }

  @override
  Future<UserProfile> removeAvatar(String id) async {
    final previous = await _currentAvatarUrl(id);
    // Row first here, and for the same reason the order is reversed above: what
    // the member asked for is to stop having a photo. Clearing the column
    // achieves that even if the sweep then fails, and re-running Remove would
    // find nothing left to point at.
    await supabase.from('profiles').update({'avatar_url': null}).eq('id', id);
    await _sweep(previous);
    return profileById(id);
  }

  /// The URL currently on the row — read fresh rather than taken from whatever
  /// the screen was holding, because the screen's copy can be minutes old and
  /// this value decides which object gets deleted.
  Future<String?> _currentAvatarUrl(String id) async {
    final row = await supabase
        .from('profiles')
        .select('avatar_url')
        .eq('id', id)
        .single();
    return ownAvatarUrl(row['avatar_url'] as String?);
  }

  /// Deletes the object behind [url], if it is one of ours and still named.
  ///
  /// Deliberately swallows its failure. Every caller reaches this having
  /// already done the thing the member asked for; an orphaned object is a
  /// storage bill, not a broken profile, and the log line is what makes it
  /// findable. It cannot delete anyone else's object even if the URL were
  /// tampered with — the storage policy checks the folder against `auth.uid()`,
  /// and [ownAvatarUrl] has already refused anything outside the bucket.
  Future<void> _sweep(String? url) async {
    final key = avatarObjectKey(url);
    if (key == null) return;
    try {
      await supabase.storage.from(_avatarBucket).remove([key]);
    } catch (error, stack) {
      AppLogger.warn(
        'PW-PROFILE',
        'orphaned avatar object left in storage: $key',
        error,
        stack,
      );
    }
  }

  /// v4, from the platform's secure RNG. `crypto.getRandomValues` on web,
  /// `/dev/urandom` on mobile — not `Random()`, whose sequence is guessable and
  /// which would make a public URL predictable from a neighbouring one.
  String _uuid() {
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
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
