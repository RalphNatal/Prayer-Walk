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
    bio: (row['bio'] as String?) ?? '',
    parish: (row['parish'] as String?) ?? '',
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
const profileColumns =
    'id, full_name, avatar_url, role, status, created_at, handle, bio, parish';

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
