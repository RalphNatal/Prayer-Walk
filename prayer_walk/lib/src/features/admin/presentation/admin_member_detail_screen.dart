import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/data/mock_profile_repository.dart';
import '../../profile/domain/user_profile.dart';
import '../data/mock_admin_repository.dart';
import 'widgets/status_pill.dart';

/// One member, with the two levers an admin has: role and standing.
///
/// Both are mocked — they mutate the in-memory store and confirm. Both ask
/// first, because both change what another person can do.
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

    await ref.read(adminRepositoryProvider).setRole(member.id, target);
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
          ? 'They keep their walks but cannot post, comment or encourage until '
                'this is lifted.'
          : 'They can post, comment and encourage again straight away.',
      confirmLabel: target == MemberStatus.suspended ? 'Suspend' : 'Restore',
      destructive: target == MemberStatus.suspended,
    );
    if (!confirmed) return;

    await ref.read(adminRepositoryProvider).setStatus(member.id, target);
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

    return AdminPage(
      title: member.value?.displayName ?? 'Member',
      subtitle: member.value?.handle,
      showBack: true,
      body: AsyncView<UserProfile>(
        value: member,
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
              subtitle: 'Preview build — these change local data only.',
              dense: true,
            ),
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
        ),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].$1, style: theme.textTheme.bodyMedium),
                  ),
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
