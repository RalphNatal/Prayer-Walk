/// Which experience a signed-in person lands in.
///
/// Read from the `role` column of the Supabase `profiles` row. The app only
/// ever reads it — RLS and the self-promotion trigger are what enforce it.
enum UserRole {
  member('Member'),
  admin('Admin');

  const UserRole(this.label);
  final String label;
}

enum MemberStatus {
  active('Active'),
  suspended('Suspended');

  const MemberStatus(this.label);
  final String label;
}

/// Lifetime totals shown on a profile. Derived server-side in Phase 2.
class LifetimeStats {
  const LifetimeStats({
    required this.totalDistanceMeters,
    required this.totalDuration,
    required this.activityCount,
    required this.streakDays,
    required this.intentionCount,
  });

  final double totalDistanceMeters;
  final Duration totalDuration;
  final int activityCount;
  final int streakDays;
  final int intentionCount;

  static const empty = LifetimeStats(
    totalDistanceMeters: 0,
    totalDuration: Duration.zero,
    activityCount: 0,
    streakDays: 0,
    intentionCount: 0,
  );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.role,
    required this.status,
    required this.joinedAt,
    required this.accentIndex,
    this.avatarUrl,
    this.bio = '',
    this.parish = '',
    this.pronouns = '',
    this.location = '',
    this.links = '',
    this.stats = LifetimeStats.empty,
    this.followerCount = 0,
    this.followingCount = 0,
  });

  final String id;
  final String displayName;

  /// Public handle, stored with the leading `@`.
  final String handle;
  final String bio;
  final String parish;

  /// Short, member-supplied: "she/her", "they/them". Public, like everything
  /// else on this row.
  final String pronouns;

  /// City-level and free text — a label, never coordinates. See the column
  /// comment in `20260731010000_profile_public_fields.sql` for why.
  final String location;

  /// One member-supplied URL, already scheme-checked on the way in. Still
  /// re-checked before it is offered as a link: this value can come from a row
  /// written by an older build.
  final String links;

  final UserRole role;
  final MemberStatus status;
  final DateTime joinedAt;

  /// The uploaded photo, or null for the initials avatar.
  ///
  /// Always an object in this project's own `avatars` bucket — never a
  /// third-party URL. The signup trigger used to copy Google's; it does not any
  /// more, and the ones it wrote were cleared. `UserAvatar` reads this and
  /// falls back to [initials] on null *and* on a load failure, so a swept
  /// object never leaves a hole on screen.
  final String? avatarUrl;

  /// Picks the avatar tint — the background behind [initials] when there is no
  /// photo, and the placeholder colour while one loads.
  final int accentIndex;

  final LifetimeStats stats;
  final int followerCount;
  final int followingCount;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    String first(String s) => s.substring(0, 1).toUpperCase();
    if (parts.length == 1) return first(parts.first);
    return '${first(parts.first)}${first(parts.last)}';
  }

  /// [avatarUrl] takes a sentinel rather than a plain `String?` because null is
  /// a value here, not an absence: "keep the photo you have" and "you have no
  /// photo" are different instructions, and `avatarUrl ?? this.avatarUrl` can
  /// only express the first. Pass [noAvatar] to clear it.
  UserProfile copyWith({
    String? displayName,
    String? handle,
    String? bio,
    String? parish,
    String? pronouns,
    String? location,
    String? links,
    Object? avatarUrl = _keepAvatar,
    UserRole? role,
    MemberStatus? status,
    LifetimeStats? stats,
    int? followerCount,
    int? followingCount,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt,
      accentIndex: accentIndex,
      avatarUrl: identical(avatarUrl, _keepAvatar)
          ? this.avatarUrl
          : avatarUrl as String?,
      bio: bio ?? this.bio,
      parish: parish ?? this.parish,
      pronouns: pronouns ?? this.pronouns,
      location: location ?? this.location,
      links: links ?? this.links,
      stats: stats ?? this.stats,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }

  /// Pass as `copyWith(avatarUrl: UserProfile.noAvatar)` to remove the photo.
  static const Object? noAvatar = null;

  /// The "you did not mention it" marker for [copyWith]'s `avatarUrl`. Private
  /// and identity-compared, so no caller can pass it by accident.
  static const Object _keepAvatar = Object();
}
