import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../profile/data/profile_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../data/admin_providers.dart';
import 'widgets/status_pill.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ADMINMEMBER';

/// One member, with the two levers an admin has: role and standing.
///
/// Both write to the real `profiles` row, and both ask first, because both
/// change what another person can do. Neither is enforced here: the role
/// trigger and the admin update policy decide, and this screen's job is to
/// state the consequence beforehand and report the database's answer honestly
/// afterwards.
class AdminMemberDetailScreen extends ConsumerWidget {
  const AdminMemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    UserProfile member,
  ) async {
    final target = member.role == UserRole.admin
        ? UserRole.member
        : UserRole.admin;

    final confirmed = await showConfirmDialog(
      context,
      title: target == UserRole.admin ? 'Make admin?' : 'Remove admin?',
      message: target == UserRole.admin
          ? '${member.displayName} will get the admin console: members, '
                'content, moderation and announcements.'
          : '${member.displayName} loses access to the admin console and goes '
                'back to the member app.',
      confirmLabel: target == UserRole.admin ? 'Make admin' : 'Remove admin',
      destructive: target == UserRole.member,
    );
    if (!confirmed) return;

    try {
      await ref.read(adminRepositoryProvider).setRole(member.id, target);
    } catch (error, stack) {
      // The role trigger's own sentence comes through here — "You cannot change
      // your own role", "Only an admin can change a member's role". Showing it
      // verbatim is the point: it names the rule that refused.
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That role change didn't go through.",
        );
      }
      return;
    }
    _refresh(ref, member.id);
    if (context.mounted) {
      showAppSnackBar(
        context,
        '${member.displayName} is now ${target.label.toLowerCase()}.',
      );
    }
  }

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    UserProfile member,
  ) async {
    final target = member.status == MemberStatus.suspended
        ? MemberStatus.active
        : MemberStatus.suspended;

    final confirmed = await showConfirmDialog(
      context,
      title: target == MemberStatus.suspended
          ? 'Suspend ${member.displayName}?'
          : 'Restore ${member.displayName}?',
      message: target == MemberStatus.suspended
          ? 'They keep their walks and can still read, but cannot record, '
                'comment, encourage or follow until this is lifted.'
          : 'They can record, comment, encourage and follow again straight '
                'away.',
      confirmLabel: target == MemberStatus.suspended ? 'Suspend' : 'Restore',
      destructive: target == MemberStatus.suspended,
    );
    if (!confirmed) return;

    try {
      await ref.read(adminRepositoryProvider).setStatus(member.id, target);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: target == MemberStatus.suspended
              ? "${member.displayName} wasn't suspended."
              : "${member.displayName} wasn't restored.",
        );
      }
      return;
    }
    _refresh(ref, member.id);
    if (context.mounted) {
      showAppSnackBar(
        context,
        target == MemberStatus.suspended
            ? '${member.displayName} suspended.'
            : '${member.displayName} restored.',
      );
    }
  }

  /// The console and the member app read the same `profiles` row now, so both
  /// have to be told it moved — a suspension that leaves the member's own
  /// profile screen showing "Active" is the same lie by another route.
  void _refresh(WidgetRef ref, String id) {
    ref
      ..invalidate(adminMemberProvider(id))
      ..invalidate(adminMembersProvider)
      ..invalidate(adminMetricsProvider)
      ..invalidate(profileProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(adminMemberProvider(memberId));
    final activityCount = ref.watch(memberActivityCountProvider(memberId));
    final isSelf = ref.watch(currentAuthUserIdProvider) == memberId;

    return AdminPage(
      title: member.value?.displayName ?? 'Member',
      subtitle: member.value?.handle,
      showBack: true,
      body: AsyncView<UserProfile>(
        value: member,
        errorFallback: "That member's record couldn't be loaded.",
        onRetry: () => ref.invalidate(adminMemberProvider(memberId)),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              children: [
                ListRowSkeleton(leadingSize: 64),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox(height: 120),
              ],
            ),
          ),
        ),
        data: (item) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  initials: item.initials,
                  accentIndex: item.accentIndex,
                  size: AppSizes.avatarLg,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        item.handle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          StatusPill(
                            label: item.role.label,
                            tone: item.role == UserRole.admin
                                ? PillTone.info
                                : PillTone.neutral,
                          ),
                          StatusPill(
                            label: item.status.label,
                            tone: item.status == MemberStatus.active
                                ? PillTone.success
                                : PillTone.danger,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            _DetailTable(
              rows: [
                ('Parish', item.parish.isEmpty ? '—' : item.parish),
                ('Joined', Fmt.dayMonthYear(item.joinedAt)),
                (
                  'Activities logged',
                  activityCount.value?.toString() ?? '…',
                ),
                (
                  'Lifetime distance',
                  Fmt.distance(item.stats.totalDistanceMeters),
                ),
                ('Followers', Fmt.count(item.followerCount)),
                ('Following', Fmt.count(item.followingCount)),
              ],
            ),

            if (item.bio.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Bio', dense: true),
              Text(item.bio, style: Theme.of(context).textTheme.bodyMedium),
            ],

            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(
              title: 'Actions',
              subtitle: 'These take effect immediately, for this member.',
              dense: true,
            ),

            // Your own row offers no role control, because the database will
            // not accept one. Nobody changes their own role — that is what
            // keeps self-promotion impossible, and what stops the last admin
            // demoting themselves and locking the console. Saying so here is
            // cheaper than letting someone tap it and read an error.
            if (isSelf)
              _SelfNote(
                text:
                    "This is you. Role changes have to come from another "
                    "admin — nobody can change their own, which is what keeps "
                    "the console from ever being left without one.",
              )
            else ...[
              SecondaryButton(
                label: item.role == UserRole.admin
                    ? 'Remove admin access'
                    : 'Make admin',
                icon: Icons.shield_outlined,
                expand: true,
                onPressed: () => _changeRole(context, ref, item),
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: item.status == MemberStatus.suspended
                    ? 'Restore member'
                    : 'Suspend member',
                icon: item.status == MemberStatus.suspended
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                expand: true,
                onPressed: () => _changeStatus(context, ref, item),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Why there are no controls here, in one sentence, where the controls would
/// have been.
class _SelfNote extends StatelessWidget {
  const _SelfNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _DetailTable extends StatelessWidget {
  const _DetailTable({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              // Label left, value right — until they no longer fit, at which
              // point the value drops to its own line rather than running off
              // the card. "San Roque Parish, Mandaluyong" beside "Parish" is
              // wider than a 320dp phone before the text scale is touched.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xxs,
                children: [
                  Text(rows[i].$1, style: theme.textTheme.bodyMedium),
                  Text(rows[i].$2, style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
