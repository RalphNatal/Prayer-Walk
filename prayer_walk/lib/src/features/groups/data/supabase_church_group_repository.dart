import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/secure_id.dart';
import '../../profile/data/avatar_image.dart' show CoverUpload;
import '../../profile/domain/profile_repository.dart' show AvatarUpload;
import '../../scripture/data/scripture_row_mapper.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../domain/church_group.dart';
import '../domain/church_group_fields.dart';
import '../domain/church_group_repository.dart';
import 'church_group_row_mapper.dart';

/// The bucket created by `20261016010000_church_groups.sql`.
const _bucket = 'church-groups';

const _tag = 'PW-GROUPS';

/// Church groups, through the RPCs and policies in
/// `20261016010000_church_groups.sql` and `20261016020000_group_scripture.sql`.
///
/// Reads go through the `church_group_card` functions so a group arrives with
/// its member count and the viewer's standing in one round trip. Writes go to
/// the tables directly wherever a policy can judge them, and through an RPC
/// only where it cannot: creating a hidden group (its founder cannot read it
/// back until a trigger has run) and joining by code (the code is the
/// permission, and it is not readable to the person holding it).
class SupabaseChurchGroupRepository implements ChurchGroupRepository {
  const SupabaseChurchGroupRepository(this._viewerId);

  final String? _viewerId;

  String get _me {
    final id = _viewerId;
    if (id == null) {
      throw const AppException('Sign in again, then try that once more.');
    }
    return id;
  }

  // ------------------------------------------------------------- finding ---

  @override
  Future<List<ChurchGroup>> searchGroups(String query, {int limit = 30}) async {
    if (_viewerId == null) return const [];
    final rows =
        await supabase.rpc(
              'search_church_groups',
              params: {'query': query.trim(), 'limit_count': limit},
            )
            as List<dynamic>;
    return churchGroupsFromRows(rows);
  }

  @override
  Future<List<ChurchGroup>> myGroups() async {
    if (_viewerId == null) return const [];
    final rows = await supabase.rpc('my_church_groups') as List<dynamic>;
    return churchGroupsFromRows(rows);
  }

  @override
  Future<ChurchGroup> groupById(String id) async {
    final rows =
        await supabase.rpc('church_group_detail', params: {'group_id': id})
            as List<dynamic>;
    final groups = churchGroupsFromRows(rows);
    // Missing, removed, or hidden from this viewer — one answer for all three,
    // so the response confirms nothing about a group the reader cannot see.
    if (groups.isEmpty) throw AppException.notFound;
    return groups.single;
  }

  @override
  Future<List<ChurchGroup>> groupsForMember(String userId) async {
    if (_viewerId == null) return const [];
    final rows =
        await supabase.rpc(
              'church_groups_for_member',
              params: {'target': userId},
            )
            as List<dynamic>;
    return churchGroupsFromRows(rows);
  }

  @override
  Future<List<GroupMember>> roster(String groupId) async {
    final rows =
        await supabase.rpc('church_group_roster', params: {'group_id': groupId})
            as List<dynamic>;
    return groupMembersFromRows(rows);
  }

  // ----------------------------------------------------------- belonging ---

  @override
  Future<ChurchGroup> join(ChurchGroup group) async {
    try {
      await supabase.from('church_group_members').insert({
        'group_id': group.id,
        'user_id': _me,
        'role': GroupRole.member.wire,
        'status': joinStatusFor(group.joinPolicy),
      });
    } on PostgrestException catch (error) {
      // Already a row: joined on another device, or removed from this group.
      // Either way the truth is on the server, and re-reading shows it.
      if (error.code == '23505') return groupById(group.id);
      // The insert policy refused the status — the group changed how it
      // admits people since this screen read it. Say so plainly.
      if (error.code == '42501') {
        throw const AppException(
          "This group's joining rules just changed. Pull to refresh and try "
          'again.',
          actionLabel: 'Refresh',
        );
      }
      rethrow;
    }
    return groupById(group.id);
  }

  @override
  Future<void> leave(String groupId) async {
    await supabase
        .from('church_group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', _me);
  }

  @override
  Future<ChurchGroup?> previewByCode(String code) async {
    final normalised = normaliseInviteCode(code);
    if (normalised.isEmpty) return null;
    final rows =
        await supabase.rpc(
              'preview_church_group',
              params: {'invite_code': normalised},
            )
            as List<dynamic>;
    final groups = churchGroupsFromRows(rows);
    return groups.isEmpty ? null : groups.first;
  }

  @override
  Future<ChurchGroup> joinWithCode(String code) async {
    try {
      final rows =
          await supabase.rpc(
                'join_church_group_with_code',
                params: {'invite_code': normaliseInviteCode(code)},
              )
              as List<dynamic>;
      final groups = churchGroupsFromRows(rows);
      if (groups.isEmpty) throw AppException.notFound;
      return groups.first;
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') {
        throw const AppException(
          "That code doesn't match a group. Check it with whoever shared it — "
          'codes change when an admin makes a new one.',
          actionLabel: 'Check the code',
        );
      }
      if (error.code == '42501') {
        throw AppException(error.message, actionLabel: 'OK');
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------- running ---

  @override
  Future<ChurchGroup> createGroup(ChurchGroupDraft draft) async {
    final rows =
        await supabase.rpc(
              'create_church_group',
              params: {
                'group_name': draft.name.trim(),
                'group_city': draft.city.trim(),
                'group_about': draft.description.trim(),
                'group_discoverable': draft.isDiscoverable,
                'group_join_policy': draft.joinPolicy.wire,
              },
            )
            as List<dynamic>;
    final groups = churchGroupsFromRows(rows);
    if (groups.isEmpty) throw AppException.notFound;
    return groups.first;
  }

  @override
  Future<ChurchGroup> updateGroup(
    String groupId,
    ChurchGroupDraft draft,
  ) async {
    final rows = await supabase
        .from('church_groups')
        .update({
          'name': draft.name.trim(),
          'city': draft.city.trim(),
          'description': draft.description.trim(),
          'is_discoverable': draft.isDiscoverable,
          'join_policy': draft.joinPolicy.wire,
        })
        .eq('id', groupId)
        .select('id');
    // No row back means the update policy refused it — not this group's
    // admin any more — rather than a group that has vanished.
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
    return groupById(groupId);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final rows = await supabase
        .from('church_groups')
        .delete()
        .eq('id', groupId)
        .select('id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
  }

  @override
  Future<ChurchGroup> uploadAvatar(String groupId, AvatarUpload upload) =>
      _uploadImage(groupId, column: 'avatar_url', bytes: upload.bytes);

  @override
  Future<ChurchGroup> uploadCover(String groupId, CoverUpload upload) =>
      _uploadImage(groupId, column: 'cover_url', bytes: upload.bytes);

  /// The avatar repository's order, for the same reasons: write the object,
  /// re-point the row, then sweep the old object and let that sweep fail
  /// quietly. A failed upload leaves the group looking exactly as it did.
  Future<ChurchGroup> _uploadImage(
    String groupId, {
    required String column,
    required Uint8List bytes,
  }) async {
    final current = await supabase
        .from('church_groups')
        .select(column)
        .eq('id', groupId)
        .single();
    final previous = ownGroupImageUrl(current[column] as String?);

    final key = '$groupId/${secureUuidV4()}.jpg';
    await supabase.storage
        .from(_bucket)
        .uploadBinary(
          key,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
            cacheControl: '31536000',
          ),
        );
    final url = supabase.storage.from(_bucket).getPublicUrl(key);
    final rows = await supabase
        .from('church_groups')
        .update({column: url})
        .eq('id', groupId)
        .select('id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);

    final oldKey = groupImageObjectKey(previous);
    if (oldKey != null) {
      try {
        await supabase.storage.from(_bucket).remove([oldKey]);
      } catch (error, stack) {
        AppLogger.warn(
          _tag,
          'orphaned group image left: $oldKey',
          error,
          stack,
        );
      }
    }
    return groupById(groupId);
  }

  @override
  Future<String?> inviteCode(String groupId) async {
    final row = await supabase
        .from('church_group_invites')
        .select('code')
        .eq('group_id', groupId)
        .maybeSingle();
    return row?['code'] as String?;
  }

  @override
  Future<String> rotateInviteCode(String groupId) async {
    final code = await supabase.rpc(
      'rotate_church_group_invite',
      params: {'group_id': groupId},
    );
    if (code is! String || code.isEmpty) throw const AppException(_notAnAdmin);
    return code;
  }

  @override
  Future<void> setMemberStatus(
    String groupId,
    String userId,
    MembershipStatus status,
  ) => _updateMember(groupId, userId, {'status': status.wire});

  @override
  Future<void> setMemberRole(String groupId, String userId, GroupRole role) =>
      _updateMember(groupId, userId, {'role': role.wire});

  Future<void> _updateMember(
    String groupId,
    String userId,
    Map<String, Object> changes,
  ) async {
    final rows = await supabase
        .from('church_group_members')
        .update(changes)
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .select('user_id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
  }

  @override
  Future<void> removeMember(String groupId, String userId) async {
    final rows = await supabase
        .from('church_group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .select('user_id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
  }

  // ----------------------------------------------------------- scripture ---

  @override
  Future<List<ScripturePrompt>> groupPrompts(String groupId) async {
    final rows = await supabase
        .from('scripture_prompts')
        .select(scripturePromptColumns)
        .eq('group_id', groupId)
        .order('sort_order')
        .order('created_at', ascending: false);
    return scripturePromptsFromRows(rows);
  }

  @override
  Future<ScripturePrompt> saveGroupPrompt(GroupScriptureDraft draft) async {
    final errors = groupScriptureErrors(draft);
    if (errors.isNotEmpty) throw AppException(errors.values.first);

    final payload = <String, Object?>{
      'reference': draft.reference.trim(),
      'body': draft.body.trim(),
      // ⚖️ Taken from the explicit choice on the form, never defaulted. The
      // column default is 'WEB' from before the British edition was settled
      // on; letting it apply silently would credit a prayer to a translation.
      'translation': draft.translation.id,
      'kind': draft.kind.name,
      'category': draft.category.name,
      'is_published': draft.isPublished,
      'group_id': draft.groupId,
      // Whoever saves new text vouches for it, as themselves. The database
      // stamps the time and refuses a text change without this.
      'rights_attested_by': _me,
      'status': 'approved',
    };

    final id = draft.id;
    final row = id == null
        ? await supabase
              .from('scripture_prompts')
              .insert({...payload, 'published_by': _me})
              .select(scripturePromptColumns)
              .single()
        : await supabase
              .from('scripture_prompts')
              .update(payload)
              .eq('id', id)
              .select(scripturePromptColumns)
              .single();
    return scripturePromptFromRow(row);
  }

  @override
  Future<void> setGroupPromptPublished(
    String promptId, {
    required bool published,
  }) async {
    final rows = await supabase
        .from('scripture_prompts')
        .update({'is_published': published})
        .eq('id', promptId)
        .select('id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
  }

  @override
  Future<void> deleteGroupPrompt(String promptId) async {
    final rows = await supabase
        .from('scripture_prompts')
        .delete()
        .eq('id', promptId)
        .select('id');
    if (rows.isEmpty) throw const AppException(_notAnAdmin);
  }
}

/// What a refused admin write means in practice: the person is no longer one
/// of this group's admins (or never was, on a stale screen).
const _notAnAdmin =
    "That change wasn't allowed — you may no longer be an admin of this "
    'group. Go back and open it again.';
