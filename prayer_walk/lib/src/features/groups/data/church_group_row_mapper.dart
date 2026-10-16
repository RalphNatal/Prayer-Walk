import '../../profile/data/profile_row_mapper.dart';
import '../domain/church_group.dart';

/// Row ⇄ [ChurchGroup], in one place — `profile_row_mapper.dart`'s bargain.
///
/// Every read that returns a group returns the `church_group_card` composite:
/// the search, "your churches", one group, the groups on a profile, an invite
/// preview and a freshly created group. One shape, one mapper, so the same
/// church cannot come back with two member counts on two screens.

/// The path every image this feature stores sits under — the bucket created
/// by `20261016010000_church_groups.sql`.
const _groupBucketPath = '/storage/v1/object/public/church-groups/';

/// A group image URL the app will render, or null — for the reason
/// [ownAvatarUrl] gives: nothing on a church's page should become a request to
/// somebody else's server, and only our own objects can be swept on replace.
String? ownGroupImageUrl(String? raw) {
  final url = raw?.trim();
  if (url == null || url.isEmpty) return null;
  return url.contains(_groupBucketPath) ? url : null;
}

/// The object key behind [publicUrl] in the `church-groups` bucket, or null.
String? groupImageObjectKey(String? publicUrl) {
  final url = ownGroupImageUrl(publicUrl);
  if (url == null) return null;
  final key = url.split(_groupBucketPath).last.split('?').first;
  return key.isEmpty ? null : Uri.decodeComponent(key);
}

ChurchGroup churchGroupFromRow(Map<String, dynamic> row) {
  return ChurchGroup(
    id: row['id'] as String,
    name: (row['name'] as String?)?.trim() ?? '',
    slug: (row['slug'] as String?) ?? '',
    description: (row['description'] as String?)?.trim() ?? '',
    city: (row['city'] as String?)?.trim() ?? '',
    avatarUrl: ownGroupImageUrl(row['avatar_url'] as String?),
    coverUrl: ownGroupImageUrl(row['cover_url'] as String?),
    isDiscoverable: row['is_discoverable'] != false,
    joinPolicy: GroupJoinPolicy.fromWire(row['join_policy'] as String?),
    memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
    myRole: GroupRole.fromWire(row['my_role'] as String?),
    myStatus: MembershipStatus.fromWire(row['my_status'] as String?),
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

List<ChurchGroup> churchGroupsFromRows(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map) churchGroupFromRow(Map<String, dynamic>.from(row)),
];

/// One `church_group_roster` row. The nested profile is the same byline shape
/// every other read builds, through the same mapper.
GroupMember groupMemberFromRow(Map<String, dynamic> row) {
  return GroupMember(
    profile: userProfileFromRow(
      Map<String, dynamic>.from(row['profile'] as Map),
    ),
    role: GroupRole.fromWire(row['role'] as String?) ?? GroupRole.member,
    status:
        MembershipStatus.fromWire(row['status'] as String?) ??
        MembershipStatus.active,
    joinedAt:
        DateTime.tryParse((row['joined_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

List<GroupMember> groupMembersFromRows(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map) groupMemberFromRow(Map<String, dynamic>.from(row)),
];

/// What a self-join sends as its status: the server's rule, stated by the
/// client so the insert policy can check it rather than trust it.
String joinStatusFor(GroupJoinPolicy policy) => switch (policy) {
  GroupJoinPolicy.open => MembershipStatus.active.wire,
  GroupJoinPolicy.request => MembershipStatus.pending.wire,
};
