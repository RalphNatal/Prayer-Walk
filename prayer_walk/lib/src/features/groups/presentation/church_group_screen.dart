import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/domain/admin_models.dart' show ReportTargetType;
import '../../moderation/presentation/report_sheet.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../../scripture/presentation/scripture_quotation.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import '../domain/church_group_fields.dart';
import 'widgets/church_group_tile.dart';
import 'widgets/group_avatar.dart';

const _tag = 'PW-GROUPS';

/// One church's group: what it is, who walks with it, and what it shares.
///
/// The page is the decision point for joining — see [ChurchGroupTile] for why
/// the list does not join in one tap — so it says plainly what joining does
/// before the button: your church's scripture arrives on your walks.
///
/// Everything an admin can do here is also refused by the database to anyone
/// who is not one. The admin panel is shown on [ChurchGroup.isAdmin], which is
/// the server's answer about this viewer, not a guess.
class ChurchGroupScreen extends ConsumerWidget {
  const ChurchGroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(churchGroupProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        title: Text(group.value?.name ?? 'Church'),
        actions: [
          if (group.value case final loaded?) _GroupOverflow(group: loaded),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () {
          ref
            ..invalidate(groupRosterProvider(groupId))
            ..invalidate(groupPromptsProvider(groupId));
          return ref.refresh(churchGroupProvider(groupId).future);
        },
        child: AsyncView<ChurchGroup>(
          value: group,
          errorFallback: "That church couldn't be loaded.",
          onRetry: () => ref.invalidate(churchGroupProvider(groupId)),
          loading: const ChurchGroupPageSkeleton(),
          data: (loaded) => _GroupPage(group: loaded),
        ),
      ),
    );
  }
}

class _GroupPage extends StatelessWidget {
  const _GroupPage({required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const overlap = AppSizes.avatarLg / 2;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl * 2),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ChurchGroupCover(group: group),
            Positioned(
              left: AppSpacing.lg,
              bottom: -overlap,
              child: ChurchGroupAvatar(group: group, size: AppSizes.avatarLg),
            ),
          ],
        ),
        const SizedBox(height: overlap + AppSpacing.md),
        Padding(
          padding: AppSpacing.screenH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(group.name, style: theme.textTheme.displaySmall),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (group.city.isNotEmpty)
                _Detail(icon: Icons.place_outlined, text: group.city),
              _Detail(
                icon: Icons.groups_outlined,
                text: memberCountLabel(group.memberCount),
              ),
              _Detail(
                icon: group.isDiscoverable
                    ? Icons.public_outlined
                    : Icons.lock_outline_rounded,
                text: [
                  group.isDiscoverable ? 'Listed' : 'Hidden — invite code only',
                  group.joinPolicy == GroupJoinPolicy.request
                      ? 'admins approve new members'
                      : 'anyone can join',
                ].join(' · '),
              ),
              if (group.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(group.description, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: AppSpacing.xl),
              _MembershipAction(group: group),
              if (group.isAdmin) ...[
                const SizedBox(height: AppSpacing.xl),
                _AdminPanel(group: group),
              ],
              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: 'Scripture from this church',
                subtitle: group.isMember
                    ? 'Delivered on your walks alongside the app\'s library.'
                    : null,
                actionLabel: group.isAdmin ? 'Manage' : null,
                onAction: group.isAdmin
                    ? () => context.pushNamed(
                        Routes.churchGroupScripture,
                        pathParameters: {'groupId': group.id},
                      )
                    : null,
              ),
              if (group.isMember)
                _GroupScripture(group: group)
              else
                const _MembersOnly(
                  icon: Icons.menu_book_outlined,
                  text:
                      'Members receive this church\'s verses and prayers on '
                      'their walks. Join to have them arrive on yours.',
                ),
              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: 'Members',
                actionLabel: group.isMember ? 'See all' : null,
                onAction: group.isMember
                    ? () => context.pushNamed(
                        Routes.churchGroupMembers,
                        pathParameters: {'groupId': group.id},
                      )
                    : null,
              ),
              if (group.isMember)
                _RosterPreview(group: group)
              else
                const _MembersOnly(
                  icon: Icons.groups_outlined,
                  text: 'Who is in a group is visible to its members.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One icon-and-text line under the name, as on a profile.
class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Icon(
              icon,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A quiet note where members-only content would be.
class _MembersOnly extends StatelessWidget {
  const _MembersOnly({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- membership ---

/// Join, ask, waiting, joined — one button that changes what it says rather
/// than four that come and go. The change cross-fades at the app's standard
/// pace, so the state moves rather than pops.
class _MembershipAction extends ConsumerStatefulWidget {
  const _MembershipAction({required this.group});

  final ChurchGroup group;

  @override
  ConsumerState<_MembershipAction> createState() => _MembershipActionState();
}

class _MembershipActionState extends ConsumerState<_MembershipAction> {
  bool _busy = false;

  ChurchGroup get _group => widget.group;

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final joined = await ref.read(churchGroupActionsProvider).join(_group);
      if (mounted) {
        showAppSnackBar(
          context,
          joined.isPending
              ? 'Request sent. An admin of ${_group.name} will let you in.'
              : "Welcome. ${_group.name}'s scripture will join your walks.",
        );
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "You weren't added to ${_group.name}.",
          onRetry: _join,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final pending = _group.isPending;
    final confirmed = await showConfirmDialog(
      context,
      title: pending ? 'Withdraw your request?' : 'Leave ${_group.name}?',
      message: pending
          ? 'Your request to join is taken back. You can ask again later.'
          : _group.isAdmin
          ? "Its scripture stops arriving on your walks. If nobody else looks "
                'after the group, its longest-standing member becomes its '
                "admin — and if you're the last member, the group closes."
          : 'Its scripture stops arriving on your walks. You can join again '
                'whenever you like.',
      confirmLabel: pending ? 'Withdraw' : 'Leave',
      destructive: !pending,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(churchGroupActionsProvider).leave(_group.id);
      if (mounted) {
        showAppSnackBar(
          context,
          pending ? 'Request withdrawn.' : 'You left ${_group.name}.',
        );
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: pending
              ? "Your request wasn't withdrawn."
              : "You're still in ${_group.name}.",
          onRetry: _leave,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget action;
    if (_group.isBanned) {
      action = Text(
        'You were removed from this group.',
        key: const ValueKey('banned'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    } else if (_group.isMember) {
      action = SecondaryButton(
        key: const ValueKey('joined'),
        label: _group.isAdmin ? 'Joined · admin' : 'Joined',
        icon: Icons.check_rounded,
        expand: true,
        busy: _busy,
        onPressed: _leave,
      );
    } else if (_group.isPending) {
      action = SecondaryButton(
        key: const ValueKey('pending'),
        label: 'Request sent',
        icon: Icons.hourglass_top_rounded,
        expand: true,
        busy: _busy,
        onPressed: _leave,
      );
    } else {
      action = PrimaryButton(
        key: const ValueKey('join'),
        label: _group.joinPolicy == GroupJoinPolicy.request
            ? 'Ask to join'
            : 'Join',
        icon: Icons.add_rounded,
        expand: true,
        busy: _busy,
        semanticLabel: 'Join ${_group.name}',
        onPressed: _join,
      );
    }

    return AnimatedSwitcher(
      duration: AppMotion.standard,
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: action,
    );
  }
}

// --------------------------------------------------------------- admin ---

/// What a group admin can do, gathered in one card so it never mixes into
/// what every member sees.
class _AdminPanel extends ConsumerWidget {
  const _AdminPanel({required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref
            .watch(groupRosterProvider(group.id))
            .value
            ?.where((m) => m.status == MembershipStatus.pending)
            .length ??
        0;
    final path = {'groupId': group.id};

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: SectionHeader(
              title: 'You look after this group',
              subtitle: 'Only its admins see this.',
              dense: true,
              padding: EdgeInsets.zero,
            ),
          ),
          _AdminRow(
            icon: Icons.how_to_reg_outlined,
            title: 'Members',
            subtitle: pending == 0
                ? 'Roles, removals'
                : '${Fmt.plural(pending, 'request')} waiting',
            highlight: pending > 0,
            onTap: () => context.pushNamed(
              Routes.churchGroupMembers,
              pathParameters: path,
            ),
          ),
          _AdminRow(
            icon: Icons.menu_book_outlined,
            title: 'Scripture',
            subtitle: 'What reaches your members on their walks',
            onTap: () => context.pushNamed(
              Routes.churchGroupScripture,
              pathParameters: path,
            ),
          ),
          _AdminRow(
            icon: Icons.key_rounded,
            title: 'Invite code',
            subtitle: group.isDiscoverable
                ? 'A shortcut in for people you invite'
                : 'The only way into a hidden group',
            onTap: () => showInviteCodeSheet(context, group),
          ),
          _AdminRow(
            icon: Icons.edit_outlined,
            title: 'Edit details',
            subtitle: 'Name, picture, who can join',
            onTap: () =>
                context.pushNamed(Routes.editChurchGroup, pathParameters: path),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: highlight
            ? theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// The code, large enough to read aloud, with copy and replace.
Future<void> showInviteCodeSheet(BuildContext context, ChurchGroup group) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _InviteCodeSheet(group: group),
  );
}

class _InviteCodeSheet extends ConsumerStatefulWidget {
  const _InviteCodeSheet({required this.group});

  final ChurchGroup group;

  @override
  ConsumerState<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends ConsumerState<_InviteCodeSheet> {
  bool _rotating = false;

  Future<void> _rotate() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Make a new code?',
      message:
          'The current code stops working at once. Anyone you gave it to and '
          "who hasn't joined yet will need the new one.",
      confirmLabel: 'Make new code',
    );
    if (!confirmed || !mounted) return;
    setState(() => _rotating = true);
    try {
      await ref
          .read(churchGroupActionsProvider)
          .rotateInviteCode(widget.group.id);
      if (mounted) {
        showAppSnackBar(context, 'New code made. The old one is off.');
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "A new code wasn't made.",
          onRetry: _rotate,
        );
      }
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = ref.watch(groupInviteCodeProvider(widget.group.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Invite code', style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Share it in person or in a message. Whoever enters it in '
              'Discover → Churches → Join with a code can join '
              '${widget.group.name}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AsyncView<String?>(
              value: code,
              errorFallback: "The code couldn't be loaded.",
              onRetry: () =>
                  ref.invalidate(groupInviteCodeProvider(widget.group.id)),
              loading: const ShimmerScope(child: SkeletonBox(height: 56)),
              isEmpty: (value) => value == null,
              empty: () => Text(
                'Only an admin of this group can see its code.',
                style: theme.textTheme.bodyMedium,
              ),
              data: (value) {
                final shown = formatInviteCode(value!);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppRadius.control,
                      ),
                      child: SelectableText(
                        shown,
                        textAlign: TextAlign.center,
                        semanticsLabel:
                            'Invite code ${shown.split('').join(' ')}',
                        style: AppTypography.statValue(
                          theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Copy code',
                      icon: Icons.copy_rounded,
                      expand: true,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: shown));
                        if (context.mounted) {
                          showAppSnackBar(context, 'Code copied.');
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppTextButton(
                      label: 'Make a new code',
                      icon: Icons.refresh_rounded,
                      onPressed: _rotating ? null : _rotate,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ overflow ---

enum _GroupMenu { invite, edit, report, leave }

class _GroupOverflow extends ConsumerWidget {
  const _GroupOverflow({required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_GroupMenu>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (choice) async {
        switch (choice) {
          case _GroupMenu.invite:
            await showInviteCodeSheet(context, group);
          case _GroupMenu.edit:
            await context.pushNamed(
              Routes.editChurchGroup,
              pathParameters: {'groupId': group.id},
            );
          case _GroupMenu.report:
            await showReportSheet(
              context,
              ref,
              targetType: ReportTargetType.group,
              targetId: group.id,
            );
          case _GroupMenu.leave:
            try {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Leave ${group.name}?',
                message: 'Its scripture stops arriving on your walks.',
                confirmLabel: 'Leave',
                destructive: true,
              );
              if (!confirmed) return;
              await ref.read(churchGroupActionsProvider).leave(group.id);
              if (context.mounted) {
                showAppSnackBar(context, 'You left ${group.name}.');
              }
            } catch (error, stack) {
              if (context.mounted) {
                reportFailure(
                  context,
                  error,
                  stack,
                  tag: _tag,
                  fallback: "You're still in ${group.name}.",
                );
              }
            }
        }
      },
      itemBuilder: (context) => [
        if (group.isAdmin) ...[
          const PopupMenuItem(
            value: _GroupMenu.invite,
            child: Text('Invite code'),
          ),
          const PopupMenuItem(
            value: _GroupMenu.edit,
            child: Text('Edit details'),
          ),
        ],
        if (!group.isAdmin)
          const PopupMenuItem(
            value: _GroupMenu.report,
            child: Text('Report this group'),
          ),
        if (group.isMember)
          const PopupMenuItem(
            value: _GroupMenu.leave,
            child: Text('Leave group'),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------- scripture ---

class _GroupScripture extends ConsumerWidget {
  const _GroupScripture({required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<ScripturePrompt>>(
      value: ref.watch(groupPromptsProvider(group.id)),
      errorFallback: "This church's scripture couldn't be loaded.",
      onRetry: () => ref.invalidate(groupPromptsProvider(group.id)),
      // Drafts are listed to admins on the Scripture screen, not here: this is
      // what members are actually receiving.
      isEmpty: (items) => !items.any((p) => p.isPublished),
      loading: const RowListLoading(count: 2, leadingSize: 0),
      empty: () => EmptyState(
        compact: true,
        icon: Icons.menu_book_outlined,
        title: 'Nothing shared yet',
        message: group.isAdmin
            ? 'Share a verse or a prayer of your own, and it reaches every '
                  'member on their walks.'
            : "When this church's admins share a verse or a prayer, it "
                  'reaches you on your walks — and appears here.',
        actionLabel: group.isAdmin ? 'Share scripture' : null,
        onAction: group.isAdmin
            ? () => context.pushNamed(
                Routes.churchGroupScriptureCompose,
                pathParameters: {'groupId': group.id},
              )
            : null,
      ),
      data: (items) => Column(
        children: [
          for (final prompt in items.where((p) => p.isPublished).take(5)) ...[
            GroupPromptCard(prompt: prompt),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

/// One of a group's verses or prayers, drawn through the attribution seam.
class GroupPromptCard extends StatelessWidget {
  const GroupPromptCard({super.key, required this.prompt, this.trailing});

  final ScripturePrompt prompt;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                prompt.kind == ScripturePromptKind.prayer
                    ? Icons.self_improvement_rounded
                    : Icons.menu_book_rounded,
                size: 16,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  prompt.reference,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ScriptureQuotation(
            text: prompt.body,
            translationId: prompt.translation,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          TranslationCredit(
            translationId: prompt.translation,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- roster ---

class _RosterPreview extends ConsumerWidget {
  const _RosterPreview({required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<GroupMember>>(
      value: ref.watch(groupRosterProvider(group.id)),
      errorFallback: "The members couldn't be loaded.",
      onRetry: () => ref.invalidate(groupRosterProvider(group.id)),
      loading: const RowListLoading(count: 3, leadingSize: AppSizes.avatarSm),
      data: (members) {
        final active = members
            .where((m) => m.status == MembershipStatus.active)
            .take(6)
            .toList();
        return Column(
          children: [
            for (final member in active) GroupMemberRow(member: member),
          ],
        );
      },
    );
  }
}

/// A person on a group's roster. Shared by the page's preview and the full
/// members screen, so a member looks the same in both.
class GroupMemberRow extends StatelessWidget {
  const GroupMemberRow({super.key, required this.member, this.trailing});

  final GroupMember member;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final person = member.profile;
    final since = member.status == MembershipStatus.pending
        ? 'asked ${Fmt.relativeTime(member.joinedAt)}'
        : 'since ${Fmt.dayMonthYear(member.joinedAt)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      leading: UserAvatar(
        initials: person.initials,
        accentIndex: person.accentIndex,
        imageUrl: person.avatarUrl,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isAdmin) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Admin',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${person.handle}  ·  $since',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: trailing,
      onTap: () => context.pushNamed(
        Routes.userProfile,
        pathParameters: {'userId': person.id},
      ),
    );
  }
}
