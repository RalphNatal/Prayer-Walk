import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import 'widgets/group_avatar.dart';

/// The churches a member belongs to, on their profile.
///
/// On someone else's profile this is what the server lets the viewer know —
/// their discoverable groups, plus hidden ones the two share — and the whole
/// section disappears when that is nothing, the way the suggestions strip
/// does: an empty "Churches" heading on a stranger's page says nothing true.
///
/// On your own it is never silent. No church yet is the moment to point at
/// one, so the empty state is a way in rather than an absence.
class MemberGroupsSection extends ConsumerWidget {
  const MemberGroupsSection({
    super.key,
    required this.userId,
    required this.isSelf,
  });

  final String userId;
  final bool isSelf;

  void _browse(BuildContext context) => context.pushNamed(
    Routes.discover,
    queryParameters: {Routes.discoverTabParam: Routes.discoverChurchesTab},
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsForMemberProvider(userId));

    if (!isSelf) {
      final loaded = groups.value;
      if (loaded == null || loaded.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Churches'),
          _GroupStrip(groups: loaded),
          const SizedBox(height: AppSpacing.xxl),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Your churches',
          actionLabel: 'Find more',
          onAction: () => _browse(context),
        ),
        AsyncView<List<ChurchGroup>>(
          value: groups,
          errorFallback: "Your churches couldn't be loaded.",
          onRetry: () => ref.invalidate(groupsForMemberProvider(userId)),
          isEmpty: (items) => items.isEmpty,
          loading: const RowListLoading(count: 1),
          empty: () => EmptyState(
            compact: true,
            icon: Icons.church_outlined,
            title: 'No church yet',
            message:
                "Join your church and its verses and prayers arrive on your "
                'walks. Find it by name, or start a group for it.',
            actionLabel: 'Find your church',
            onAction: () => _browse(context),
          ),
          data: (items) => _GroupStrip(groups: items),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// A wrapping row of churches — a mark and a name each — rather than a
/// horizontal scroller: there are rarely more than two or three, and a wrap
/// reflows at a large text size where a fixed-height strip would clip.
class _GroupStrip extends StatelessWidget {
  const _GroupStrip({required this.groups});

  final List<ChurchGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final group in groups)
          Semantics(
            button: true,
            label: 'Church: ${group.name}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: () => context.pushNamed(
                Routes.churchGroup,
                pathParameters: {'groupId': group.id},
              ),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.minTapTarget,
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.control,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChurchGroupAvatar(
                      group: group,
                      size: AppSizes.avatarSm,
                      outlined: false,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
