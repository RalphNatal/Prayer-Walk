import '../../profile/domain/user_profile.dart';

/// Whether joining takes effect at once or waits for an admin.
enum GroupJoinPolicy {
  open('Anyone can join', 'open'),
  request('Admins approve requests', 'request');

  const GroupJoinPolicy(this.label, this.wire);

  /// How the choice reads on the create form.
  final String label;

  /// The `church_groups.join_policy` value.
  final String wire;

  static GroupJoinPolicy fromWire(String? value) =>
      value == request.wire ? request : open;
}

/// What someone is in a group — distinct from `UserRole`, which is about the
/// app. A group admin looks after one church's group and nothing else.
enum GroupRole {
  member('Member', 'member'),
  admin('Group admin', 'admin');

  const GroupRole(this.label, this.wire);
  final String label;
  final String wire;

  static GroupRole? fromWire(String? value) => switch (value) {
    'admin' => admin,
    'member' => member,
    _ => null,
  };
}

/// Where someone stands with a group.
enum MembershipStatus {
  active('Member', 'active'),
  pending('Requested', 'pending'),
  banned('Removed', 'banned');

  const MembershipStatus(this.label, this.wire);
  final String label;
  final String wire;

  static MembershipStatus? fromWire(String? value) => switch (value) {
    'active' => active,
    'pending' => pending,
    'banned' => banned,
    _ => null,
  };
}

/// One church's group, joined for the viewer.
///
/// The counterpart to `MemberCard`: [myRole] and [myStatus] ride along on the
/// same row so a list can offer Join or Leave on every result without a second
/// query per group. Both are null when the viewer has no relationship with the
/// group at all.
class ChurchGroup {
  const ChurchGroup({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    this.description = '',
    this.city = '',
    this.avatarUrl,
    this.coverUrl,
    this.isDiscoverable = true,
    this.joinPolicy = GroupJoinPolicy.open,
    this.memberCount = 0,
    this.myRole,
    this.myStatus,
  });

  final String id;
  final String name;

  /// URL-safe and permanent — set by the server from the first name the group
  /// had, and kept when it is renamed so a shared link keeps working.
  final String slug;
  final String description;

  /// Helps tell apart the several St Josephs a search will find.
  final String city;

  /// Objects in this project's own `church-groups` bucket, or null. Anything
  /// else is dropped by the mapper, for the reason `ownAvatarUrl` gives.
  final String? avatarUrl;
  final String? coverUrl;

  /// False: reachable by invite code only, and never listed in search.
  final bool isDiscoverable;
  final GroupJoinPolicy joinPolicy;

  /// Active members. The one thing about a roster a non-member is told.
  final int memberCount;

  final GroupRole? myRole;
  final MembershipStatus? myStatus;
  final DateTime createdAt;

  bool get isMember => myStatus == MembershipStatus.active;

  /// A group admin of *this* group, and only while active.
  bool get isAdmin => isMember && myRole == GroupRole.admin;

  bool get isPending => myStatus == MembershipStatus.pending;

  bool get isBanned => myStatus == MembershipStatus.banned;

  /// Whether a Join button means anything. A banned member's row is still
  /// there, and the server refuses a second one.
  bool get canJoin => myStatus == null;

  /// "St Anne, Antipolo" — what a stranger needs to place it.
  String get placeLine => city.trim().isEmpty ? name : '$name, ${city.trim()}';

  /// Initials for the lettered avatar, the same rule people get.
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w[0].toUpperCase() != w[0].toLowerCase())
        .toList(growable: false);
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  /// A stable tint from the id, like a member's — see `accentIndexFor`.
  int get accentIndex {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x1fffffff;
    }
    return hash % 6;
  }

  ChurchGroup copyWith({
    String? name,
    String? description,
    String? city,
    Object? avatarUrl = _keep,
    Object? coverUrl = _keep,
    bool? isDiscoverable,
    GroupJoinPolicy? joinPolicy,
    int? memberCount,
    Object? myRole = _keep,
    Object? myStatus = _keep,
  }) {
    return ChurchGroup(
      id: id,
      slug: slug,
      createdAt: createdAt,
      name: name ?? this.name,
      description: description ?? this.description,
      city: city ?? this.city,
      avatarUrl: identical(avatarUrl, _keep)
          ? this.avatarUrl
          : avatarUrl as String?,
      coverUrl: identical(coverUrl, _keep)
          ? this.coverUrl
          : coverUrl as String?,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
      joinPolicy: joinPolicy ?? this.joinPolicy,
      memberCount: memberCount ?? this.memberCount,
      myRole: identical(myRole, _keep) ? this.myRole : myRole as GroupRole?,
      myStatus: identical(myStatus, _keep)
          ? this.myStatus
          : myStatus as MembershipStatus?,
    );
  }

  /// The "you did not mention it" marker for [copyWith]'s nullable fields,
  /// where null is a value rather than an absence — as in `UserProfile`.
  static const Object _keep = Object();
}

/// One person on a group's roster.
class GroupMember {
  const GroupMember({
    required this.profile,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  final UserProfile profile;
  final GroupRole role;
  final MembershipStatus status;

  /// When they were let in — set by the server, and the order the succession
  /// rule promotes in when a group loses its last admin.
  final DateTime joinedAt;

  bool get isAdmin =>
      role == GroupRole.admin && status == MembershipStatus.active;
}
