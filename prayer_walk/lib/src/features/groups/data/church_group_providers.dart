import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_haptics.dart';
import '../../auth/data/auth_providers.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../domain/church_group.dart';
import '../domain/church_group_fields.dart';
import '../domain/church_group_repository.dart';
import 'supabase_church_group_repository.dart';

final churchGroupRepositoryProvider = Provider<ChurchGroupRepository>(
  (ref) => SupabaseChurchGroupRepository(ref.watch(currentAuthUserIdProvider)),
);

/// What is typed in the Churches search field. A notifier for the reason
/// `MemberSearchQuery` is one: the result provider watches it.
class GroupSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final groupSearchQueryProvider = NotifierProvider<GroupSearchQuery, String>(
  GroupSearchQuery.new,
);

/// Discoverable groups for the current term — or, with no term, the largest
/// ones, so the tab is never a blank field waiting for a guess.
final groupSearchProvider = FutureProvider.autoDispose<List<ChurchGroup>>((
  ref,
) {
  final query = ref.watch(groupSearchQueryProvider);
  return ref.watch(churchGroupRepositoryProvider).searchGroups(query);
});

/// The largest discoverable groups — the Churches tab before anything is
/// typed. Its own provider rather than [groupSearchProvider] with an empty
/// term, so clearing the field never shows the last search's results under
/// the "all churches" heading while the debounce catches up.
final listedGroupsProvider = FutureProvider.autoDispose<List<ChurchGroup>>(
  (ref) => ref.watch(churchGroupRepositoryProvider).searchGroups(''),
);

/// The groups the signed-in member is in or waiting on. Read by the Churches
/// tab and the profile, so not auto-disposed: bouncing between the two should
/// not re-fetch the same handful.
final myGroupsProvider = FutureProvider<List<ChurchGroup>>(
  (ref) => ref.watch(churchGroupRepositoryProvider).myGroups(),
);

final churchGroupProvider = FutureProvider.autoDispose
    .family<ChurchGroup, String>(
      (ref, id) => ref.watch(churchGroupRepositoryProvider).groupById(id),
    );

final groupRosterProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>(
      (ref, id) => ref.watch(churchGroupRepositoryProvider).roster(id),
    );

final groupsForMemberProvider = FutureProvider.autoDispose
    .family<List<ChurchGroup>, String>(
      (ref, userId) =>
          ref.watch(churchGroupRepositoryProvider).groupsForMember(userId),
    );

final groupPromptsProvider = FutureProvider.autoDispose
    .family<List<ScripturePrompt>, String>(
      (ref, groupId) =>
          ref.watch(churchGroupRepositoryProvider).groupPrompts(groupId),
    );

final groupInviteCodeProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, groupId) =>
          ref.watch(churchGroupRepositoryProvider).inviteCode(groupId),
    );

/// Group mutations, the haptic that confirms each, and the invalidations that
/// keep every surface honest — `SocialActions`' arrangement.
///
/// Joining and leaving also invalidate the walk's scripture library: a group's
/// verses are part of what the next walk draws from, and a member who joins
/// their church on the record screen should hear its scripture on that walk,
/// not the one after an app restart.
///
/// Nothing here swallows a failure. The screens report through
/// `reportFailure`, which carries the failure haptic; the success haptics are
/// here so they fire only once the server has agreed.
class ChurchGroupActions {
  ChurchGroupActions(this._ref);

  final Ref _ref;

  ChurchGroupRepository get _repo => _ref.read(churchGroupRepositoryProvider);

  Future<ChurchGroup> join(ChurchGroup group) async {
    final joined = await _repo.join(group);
    AppHaptics.light();
    _afterMembershipChange(group.id);
    return joined;
  }

  Future<ChurchGroup> joinWithCode(String code) async {
    final joined = await _repo.joinWithCode(code);
    AppHaptics.light();
    _afterMembershipChange(joined.id);
    return joined;
  }

  Future<void> leave(String groupId) async {
    await _repo.leave(groupId);
    AppHaptics.selection();
    _afterMembershipChange(groupId);
  }

  Future<ChurchGroup> create(ChurchGroupDraft draft) async {
    final group = await _repo.createGroup(draft);
    AppHaptics.light();
    _ref
      ..invalidate(myGroupsProvider)
      ..invalidate(listedGroupsProvider)
      ..invalidate(groupSearchProvider);
    _invalidateOwnProfileGroups();
    return group;
  }

  Future<ChurchGroup> update(String groupId, ChurchGroupDraft draft) async {
    final group = await _repo.updateGroup(groupId, draft);
    AppHaptics.light();
    _afterGroupChange(groupId);
    return group;
  }

  Future<void> delete(String groupId) async {
    await _repo.deleteGroup(groupId);
    AppHaptics.light();
    _afterMembershipChange(groupId);
  }

  Future<void> approve(String groupId, String userId) =>
      _memberChange(groupId, () => _repo.setMemberStatus(
            groupId,
            userId,
            MembershipStatus.active,
          ));

  Future<void> ban(String groupId, String userId) =>
      _memberChange(groupId, () => _repo.setMemberStatus(
            groupId,
            userId,
            MembershipStatus.banned,
          ));

  Future<void> setRole(String groupId, String userId, GroupRole role) =>
      _memberChange(groupId, () => _repo.setMemberRole(groupId, userId, role));

  Future<void> remove(String groupId, String userId) =>
      _memberChange(groupId, () => _repo.removeMember(groupId, userId));

  Future<String> rotateInviteCode(String groupId) async {
    final code = await _repo.rotateInviteCode(groupId);
    AppHaptics.light();
    _ref.invalidate(groupInviteCodeProvider(groupId));
    return code;
  }

  Future<ScripturePrompt> savePrompt(GroupScriptureDraft draft) async {
    final saved = await _repo.saveGroupPrompt(draft);
    AppHaptics.light();
    _afterScriptureChange(draft.groupId);
    return saved;
  }

  Future<void> setPromptPublished(
    String groupId,
    String promptId, {
    required bool published,
  }) async {
    await _repo.setGroupPromptPublished(promptId, published: published);
    AppHaptics.selection();
    _afterScriptureChange(groupId);
  }

  Future<void> deletePrompt(String groupId, String promptId) async {
    await _repo.deleteGroupPrompt(promptId);
    AppHaptics.light();
    _afterScriptureChange(groupId);
  }

  Future<void> _memberChange(
    String groupId,
    Future<void> Function() write,
  ) async {
    await write();
    AppHaptics.light();
    _ref
      ..invalidate(groupRosterProvider(groupId))
      ..invalidate(churchGroupProvider(groupId));
  }

  void _afterGroupChange(String groupId) {
    _ref
      ..invalidate(churchGroupProvider(groupId))
      ..invalidate(myGroupsProvider)
      ..invalidate(listedGroupsProvider)
      ..invalidate(groupSearchProvider);
    _invalidateOwnProfileGroups();
  }

  void _afterMembershipChange(String groupId) {
    _afterGroupChange(groupId);
    _ref
      ..invalidate(groupRosterProvider(groupId))
      ..invalidate(groupPromptsProvider(groupId))
      ..invalidate(loadedScriptureLibraryProvider);
  }

  void _afterScriptureChange(String groupId) {
    _ref
      ..invalidate(groupPromptsProvider(groupId))
      ..invalidate(loadedScriptureLibraryProvider);
  }

  void _invalidateOwnProfileGroups() {
    final me = _ref.read(currentAuthUserIdProvider);
    if (me != null) _ref.invalidate(groupsForMemberProvider(me));
  }
}

final churchGroupActionsProvider = Provider<ChurchGroupActions>(
  ChurchGroupActions.new,
);
