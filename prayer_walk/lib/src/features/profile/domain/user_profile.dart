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
    this.bio = '',
    this.parish = '',
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
  final UserRole role;
  final MemberStatus status;
  final DateTime joinedAt;

  /// Picks the avatar tint. No photo uploads this phase, so avatars are
  /// initials on a deterministic colour from the palette.
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

  UserProfile copyWith({
    String? displayName,
    String? handle,
    String? bio,
    String? parish,
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
      bio: bio ?? this.bio,
      parish: parish ?? this.parish,
      stats: stats ?? this.stats,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }
}
