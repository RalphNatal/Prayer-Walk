import '../domain/user_profile.dart';

/// The one place a `profiles` row becomes a [UserProfile].
///
/// Profiles arrive from four directions now — a direct select, the `author`
/// object on a feed card, an embedded comment author, a follow list — and every
/// one of them has to produce the same person. A second copy of this mapping is
/// how the same member ends up called "Walker" on one screen and by name on
/// another, or wearing two different avatar tints.
///
/// [stats], [followerCount] and [followingCount] default to honest zeros: most
/// rows arrive without them (a byline does not need a lifetime distance) and a
/// zero is true until `member_stats` says otherwise.
UserProfile userProfileFromRow(
  Map<String, dynamic> row, {
  LifetimeStats stats = LifetimeStats.empty,
  int followerCount = 0,
  int followingCount = 0,
}) {
  final id = row['id'] as String;
  final fullName = (row['full_name'] as String?)?.trim() ?? '';
  final handle = (row['handle'] as String?)?.trim() ?? '';

  return UserProfile(
    id: id,
    displayName: fullName.isEmpty ? 'Walker' : fullName,
    handle: handle.isEmpty ? fallbackHandle(fullName) : normaliseHandle(handle),
    avatarUrl: ownAvatarUrl(row['avatar_url'] as String?),
    bio: (row['bio'] as String?) ?? '',
    parish: (row['parish'] as String?) ?? '',
    // Absent rather than empty on most rows: the `author` object the feed and
    // discovery functions build carries the byline fields only, and nothing
    // draws pronouns on a byline. An empty string is the honest answer for a
    // field this row did not come with.
    pronouns: (row['pronouns'] as String?)?.trim() ?? '',
    location: (row['location'] as String?)?.trim() ?? '',
    links: (row['links'] as String?)?.trim() ?? '',
    role: (row['role'] as String?) == 'admin' ? UserRole.admin : UserRole.member,
    status: (row['status'] as String?) == 'suspended'
        ? MemberStatus.suspended
        : MemberStatus.active,
    joinedAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
    accentIndex: accentIndexFor(id),
    stats: stats,
    followerCount: followerCount,
    followingCount: followingCount,
  );
}

/// Stored with the leading `@`, whatever the person typed.
String normaliseHandle(String value) {
  final bare = value.trim().replaceAll(RegExp(r'^@+'), '').trim();
  return '@$bare';
}

/// What to show when the row has no handle yet — a new account, since the
/// new-user trigger doesn't set one. Derived, never written: it only becomes
/// real if the person saves it from Edit profile.
String fallbackHandle(String fullName) {
  final slug = fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return slug.isEmpty ? '@member' : '@$slug';
}

/// The path every avatar this app stores sits under.
const _avatarBucketPath = '/storage/v1/object/public/avatars/';

/// An `avatar_url` the app is willing to render, or null.
///
/// Null for an empty column, and — the part that matters — null for any URL
/// that is not an object in this project's own `avatars` bucket.
///
/// That check is not paranoia about the column. It is about ordering: the app
/// starts drawing `avatar_url` in this change, and the migration that clears
/// the Google URLs the old signup trigger wrote is applied by a person, on
/// their own schedule. Between the build shipping and the SQL running, a
/// trusting mapper would have every feed card fetching an image from
/// `googleusercontent.com` — one request to a third party per byline, from
/// people who use this app partly because it does not do that. A profile falls
/// back to its initials instead, which is the same thing the member sees before
/// they upload, and nobody's device tells Google what they are reading.
///
/// It also keeps the sweep honest: the replace path deletes the object behind
/// the old URL, and it can only do that safely because every URL that reaches
/// it is one of ours.
String? ownAvatarUrl(String? raw) {
  final url = raw?.trim();
  if (url == null || url.isEmpty) return null;
  return url.contains(_avatarBucketPath) ? url : null;
}

/// The storage object key inside the `avatars` bucket for [publicUrl] — the
/// `{user_id}/{uuid}.jpg` that `remove()` takes — or null if the URL is not one
/// of ours.
///
/// Parsed rather than stored: `profiles.avatar_url` is one column, the URL is
/// built from the key, and a second column holding the key would be a second
/// thing to keep in step. `Uri.decodeComponent` because Storage percent-encodes
/// the key on the way out.
String? avatarObjectKey(String? publicUrl) {
  final url = ownAvatarUrl(publicUrl);
  if (url == null) return null;
  final key = url.split(_avatarBucketPath).last;
  if (key.isEmpty) return null;
  // A query string is not part of the key. Storage does not add one today;
  // a cache-buster appended later would otherwise silently break the sweep.
  final bare = key.split('?').first;
  return bare.isEmpty ? null : Uri.decodeComponent(bare);
}

/// A stable avatar tint from the id. Same id, same colour, every launch and
/// every device — which is the whole reason there is no column for it.
int accentIndexFor(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x1fffffff;
  }
  return hash % 6;
}

/// The `profiles` columns every read selects. Kept here so the direct selects
/// and the `author` object built by the SQL functions cannot drift apart.
///
/// `pronouns`, `location` and `links` are on this list but deliberately *not*
/// added to the `author` object the SQL functions build. A byline needs a name,
/// a handle and a face; it does not need a pronoun set, and putting three more
/// columns into ten `json_build_object` calls would widen every feed row to
/// feed a profile screen that reads this list directly anyway.
/// [userProfileFromRow] treats them as absent-means-empty, so both shapes map.
const profileColumns =
    'id, full_name, avatar_url, role, status, created_at, handle, bio, parish, '
    'pronouns, location, links';

/// One row of `member_stats`, or [LifetimeStats.empty] when there is nothing to
/// read. A zero is honest; a fabricated number is not.
LifetimeStats lifetimeStatsFromRow(Map<String, dynamic>? row) {
  if (row == null) return LifetimeStats.empty;
  return LifetimeStats(
    totalDistanceMeters: (row['total_distance_meters'] as num?)?.toDouble() ?? 0,
    totalDuration: Duration(
      seconds: (row['total_duration_seconds'] as num?)?.toInt() ?? 0,
    ),
    activityCount: (row['activity_count'] as num?)?.toInt() ?? 0,
    streakDays: (row['streak_days'] as num?)?.toInt() ?? 0,
    intentionCount: (row['intention_count'] as num?)?.toInt() ?? 0,
  );
}
