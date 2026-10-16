import '../../profile/data/avatar_image.dart' show CoverUpload;
import '../../profile/domain/profile_repository.dart' show AvatarUpload;
import '../../scripture/domain/scripture_prompt.dart';
import 'church_group.dart';
import 'church_group_fields.dart';

/// Church groups: finding one, belonging to one, and — for a group's own
/// admins — looking after it.
///
/// Every rule that matters is the database's. Whether a join is active or
/// pending, who may approve it, who may change a role, what a group admin may
/// publish: all of it is decided by the policies and triggers in
/// `20261016010000_church_groups.sql` and `20261016020000_group_scripture.sql`.
/// An implementation of this interface moves requests and maps answers; it
/// never decides who is allowed.
abstract interface class ChurchGroupRepository {
  // ------------------------------------------------------------- finding ---

  /// Discoverable groups matching [query] by name or city. An empty query
  /// lists the largest groups first — a group that chose to be discoverable
  /// asked to be listed, which a person did not.
  Future<List<ChurchGroup>> searchGroups(String query, {int limit});

  /// Groups the viewer is in or has asked to join.
  Future<List<ChurchGroup>> myGroups();

  /// One group, or [AppException.notFound] if the viewer may not see it.
  Future<ChurchGroup> groupById(String id);

  /// The groups [userId] belongs to, as far as the viewer may know: their
  /// discoverable groups, plus hidden ones the viewer shares with them.
  Future<List<ChurchGroup>> groupsForMember(String userId);

  /// The roster. Active members to fellow members; pending and removed rows
  /// too, to the group's admins.
  Future<List<GroupMember>> roster(String groupId);

  // ----------------------------------------------------------- belonging ---

  /// Joins [group] as the signed-in member. Returns the group as it now
  /// stands — `myStatus` is pending for a group that asks first.
  ///
  /// Takes the group rather than its id because the row sent has to state the
  /// status the group's policy dictates, and the database refuses any other.
  /// The client reading the policy is not the client deciding it: if the
  /// policy changed since [group] was read, the insert is refused and the
  /// screen re-reads.
  Future<ChurchGroup> join(ChurchGroup group);

  /// Leaves. If the viewer was the last admin, the server hands the group to
  /// its longest-standing member, or closes it if nobody is left.
  Future<void> leave(String groupId);

  /// What [code] opens, without joining. Null if it matches nothing.
  Future<ChurchGroup?> previewByCode(String code);

  /// Joins the group behind [code] — the only way into a hidden group.
  Future<ChurchGroup> joinWithCode(String code);

  // ------------------------------------------------------------- running ---

  Future<ChurchGroup> createGroup(ChurchGroupDraft draft);

  Future<ChurchGroup> updateGroup(String groupId, ChurchGroupDraft draft);

  Future<void> deleteGroup(String groupId);

  Future<ChurchGroup> uploadAvatar(String groupId, AvatarUpload upload);

  Future<ChurchGroup> uploadCover(String groupId, CoverUpload upload);

  /// The group's invite code, for its admins. Null for anyone else.
  Future<String?> inviteCode(String groupId);

  /// A new code; the old one stops working at once.
  Future<String> rotateInviteCode(String groupId);

  Future<void> setMemberStatus(
    String groupId,
    String userId,
    MembershipStatus status,
  );

  Future<void> setMemberRole(String groupId, String userId, GroupRole role);

  Future<void> removeMember(String groupId, String userId);

  // ----------------------------------------------------------- scripture ---

  /// A group's prompts. Its admins get drafts too; members get what is live.
  Future<List<ScripturePrompt>> groupPrompts(String groupId);

  Future<ScripturePrompt> saveGroupPrompt(GroupScriptureDraft draft);

  Future<void> setGroupPromptPublished(String promptId, {required bool published});

  Future<void> deleteGroupPrompt(String promptId);
}
