import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import 'church_group_screen.dart' show GroupMemberRow;

const _tag = 'PW-GROUPS';

/// Who is in a group.
///
/// Every member sees the roster. A group's admins also see who is waiting and
/// who was removed, and get the controls: approve, decline, make admin, step
/// someone down, remove. The roster policy is what decides which rows arrive —
/// this screen draws what it is given and offers controls on
/// [ChurchGroup.isAdmin], and the database refuses any control used by
/// someone who is not.
class GroupMembersScreen extends ConsumerWidget {
  const GroupMembersScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(churchGroupProvider(groupId));
    final roster = ref.watch(groupRosterProvider(groupId));
    final isAdmin = group.value?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: RefreshIndicator(
        onRefresh: () {
          ref.invalidate(churchGroupProvider(groupId));
          return ref.refresh(groupRosterProvider(groupId).future);
        },
        child: AsyncView<List<GroupMember>>(
          value: roster,
          errorFallback: "The members couldn't be loaded.",
          onRetry: () => ref.invalidate(groupRosterProvider(groupId)),
          isEmpty: (items) => items.isEmpty,
          loading: const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 6),
          ),
          empty: () => ScrollableStateBody(
            child: EmptyState(
              icon: Icons.groups_outlined,
              title: 'Nobody to show',
              message: isAdmin
                  ? 'Share your invite code and the people who join appear '
                        'here.'
                  : "Members are listed here once you're in the group.",
            ),
          ),
          data: (members) =>
              _Roster(groupId: groupId, members: members, isAdmin: isAdmin),
        ),
      ),
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({
    required this.groupId,
    required this.members,
    required this.isAdmin,
  });

  final String groupId;
  final List<GroupMember> members;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentAuthUserIdProvider);
    final pending = [
      for (final m in members)
        if (m.status == MembershipStatus.pending) m,
    ];
    final admins = [
      for (final m in members)
        if (m.isAdmin) m,
    ];
    final others = [
      for (final m in members)
        if (m.status == MembershipStatus.active && !m.isAdmin) m,
    ];
    final removed = [
      for (final m in members)
        if (m.status == MembershipStatus.banned) m,
    ];

    Widget row(GroupMember member) => GroupMemberRow(
      member: member,
      trailing: isAdmin && member.profile.id != me
          ? _MemberMenu(groupId: groupId, member: member)
          : null,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.listBody,
      children: [
        if (isAdmin && pending.isNotEmpty) ...[
          SectionHeader(
            title: 'Waiting to join',
            subtitle: 'They asked to join. Let them in, or decline.',
          ),
          for (final member in pending)
            GroupMemberRow(
              member: member,
              trailing: _RequestActions(groupId: groupId, member: member),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SectionHeader(title: admins.length == 1 ? 'Admin' : 'Admins'),
        for (final member in admins) row(member),
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(
          title: 'Members',
          subtitle: others.isEmpty ? 'Nobody else yet.' : null,
        ),
        for (final member in others) row(member),
        if (isAdmin && removed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Removed',
            subtitle: "They can't rejoin unless you allow it.",
          ),
          for (final member in removed) row(member),
        ],
      ],
    );
  }
}

/// Approve and decline, side by side on the row.
class _RequestActions extends ConsumerStatefulWidget {
  const _RequestActions({required this.groupId, required this.member});

  final String groupId;
  final GroupMember member;

  @override
  ConsumerState<_RequestActions> createState() => _RequestActionsState();
}

class _RequestActionsState extends ConsumerState<_RequestActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showAppSnackBar(context, done);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That request wasn't answered.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(churchGroupActionsProvider);
    final name = widget.member.profile.displayName;
    final userId = widget.member.profile.id;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decline $name',
          icon: const Icon(Icons.close_rounded),
          onPressed: _busy
              ? null
              : () => _run(
                  () => actions.remove(widget.groupId, userId),
                  'Request declined.',
                ),
        ),
        IconButton.filledTonal(
          tooltip: 'Let $name in',
          icon: const Icon(Icons.check_rounded),
          onPressed: _busy
              ? null
              : () => _run(
                  () => actions.approve(widget.groupId, userId),
                  '$name is in.',
                ),
        ),
      ],
    );
  }
}

enum _MemberAction { makeAdmin, stepDown, remove, ban, allowBack }

/// What an admin can do to someone else's membership. Never shown on your own
/// row — nobody changes their own role or standing, and the database agrees.
class _MemberMenu extends ConsumerWidget {
  const _MemberMenu({required this.groupId, required this.member});

  final String groupId;
  final GroupMember member;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final actions = ref.read(churchGroupActionsProvider);
    final name = member.profile.displayName;
    final userId = member.profile.id;

    final (title, message, label, destructive) = switch (action) {
      _MemberAction.makeAdmin => (
        'Make $name an admin?',
        'They will be able to approve members, change roles and share '
            "scripture with the whole group. It doesn't give them anything "
            'outside this group.',
        'Make admin',
        false,
      ),
      _MemberAction.stepDown => (
        'Step $name down?',
        "They stay a member, but can't manage the group any more.",
        'Step down',
        false,
      ),
      _MemberAction.remove => (
        'Remove $name?',
        "They leave the group and stop receiving its scripture. They can ask "
            'to join again.',
        'Remove',
        true,
      ),
      _MemberAction.ban => (
        'Remove $name for good?',
        "They leave the group and can't rejoin — not even with the invite "
            'code — unless an admin allows it.',
        'Remove for good',
        true,
      ),
      _MemberAction.allowBack => (
        'Allow $name back?',
        'The block is lifted. They can join or ask to join again.',
        'Allow back',
        false,
      ),
    };

    final confirmed = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: label,
      destructive: destructive,
    );
    if (!confirmed) return;

    try {
      switch (action) {
        case _MemberAction.makeAdmin:
          await actions.setRole(groupId, userId, GroupRole.admin);
        case _MemberAction.stepDown:
          await actions.setRole(groupId, userId, GroupRole.member);
        case _MemberAction.remove:
        case _MemberAction.allowBack:
          await actions.remove(groupId, userId);
        case _MemberAction.ban:
          await actions.ban(groupId, userId);
      }
      if (context.mounted) showAppSnackBar(context, 'Done.');
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That change wasn't made.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banned = member.status == MembershipStatus.banned;
    return PopupMenuButton<_MemberAction>(
      tooltip: 'Manage ${member.profile.displayName}',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) => _act(context, ref, action),
      itemBuilder: (context) => [
        if (banned)
          const PopupMenuItem(
            value: _MemberAction.allowBack,
            child: Text('Allow back'),
          )
        else ...[
          if (member.isAdmin)
            const PopupMenuItem(
              value: _MemberAction.stepDown,
              child: Text('Step down as admin'),
            )
          else
            const PopupMenuItem(
              value: _MemberAction.makeAdmin,
              child: Text('Make admin'),
            ),
          const PopupMenuItem(
            value: _MemberAction.remove,
            child: Text('Remove from group'),
          ),
          const PopupMenuItem(
            value: _MemberAction.ban,
            child: Text('Remove for good'),
          ),
        ],
      ],
    );
  }
}
