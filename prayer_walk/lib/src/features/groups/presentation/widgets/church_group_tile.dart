import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/church_group.dart';
import 'group_avatar.dart';

/// One church in a list: its mark, its name, where it is and how many walk
/// with it, and where the viewer stands with it.
///
/// The row opens the group rather than joining from the list. Joining a church
/// is not a one-tap act the way following a person is — it changes what you
/// are given on every walk after — so the decision is taken on the page that
/// says what you are joining.
class ChurchGroupTile extends StatelessWidget {
  const ChurchGroupTile({super.key, required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final standing = MembershipBadge.labelFor(group);

    return Semantics(
      button: true,
      label: [
        group.name,
        if (group.city.isNotEmpty) group.city,
        memberCountLabel(group.memberCount),
        ?standing,
      ].join(', '),
      excludeSemantics: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        leading: ChurchGroupAvatar(group: group, outlined: false),
        title: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (group.city.isNotEmpty) group.city,
            memberCountLabel(group.memberCount),
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: standing == null ? null : MembershipBadge(group: group),
        onTap: () => context.pushNamed(
          Routes.churchGroup,
          pathParameters: {'groupId': group.id},
        ),
      ),
    );
  }
}

/// "1 member", "24 members" — counted the way a person would say it.
String memberCountLabel(int count) =>
    count == 1 ? '1 member' : '${Fmt.count(count)} members';

/// Where the viewer stands with a group, as a small label: Admin, Member,
/// Requested. Nothing for a group they have no relationship with.
class MembershipBadge extends StatelessWidget {
  const MembershipBadge({super.key, required this.group});

  final ChurchGroup group;

  static String? labelFor(ChurchGroup group) {
    if (group.isAdmin) return 'Admin';
    if (group.isMember) return 'Member';
    if (group.isPending) return 'Requested';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = labelFor(group);
    if (label == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = group.isPending
        ? (scheme.tertiaryContainer, scheme.onTertiaryContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

/// The page's silhouette while it loads: band, mark, name, two lines, button.
class ChurchGroupPageSkeleton extends StatelessWidget {
  const ChurchGroupPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: const [
          AspectRatio(aspectRatio: 3, child: SkeletonBox(radius: 0)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: AppSizes.avatarLg,
                  height: AppSizes.avatarLg,
                  radius: AppRadius.md,
                ),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(width: 220, height: 22),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox.line(width: 160),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox(
                  height: AppSizes.minTapTarget,
                  radius: AppRadius.md,
                ),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox.line(),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox.line(width: 240),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
