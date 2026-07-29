import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../privacy/data/privacy_providers.dart';
import '../../privacy/presentation/block_action.dart';
import '../../social/data/social_actions.dart';
import '../../social/data/social_providers.dart';
import '../../social/presentation/optimistic_toggle.dart';
import '../data/profile_providers.dart';
import '../domain/user_profile.dart';
import 'widgets/profile_pieces.dart';

/// Someone else's profile.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId));
    // Reachable for yourself — a follower list can lead back to you. There is
    // nothing to follow there, so the button simply isn't offered.
    final isSelf = ref.watch(currentAuthUserIdProvider) == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!isSelf) _ProfileOverflow(userId: userId, profile: profile),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(profileProvider(userId).future),
        child: AsyncView<UserProfile>(
          value: profile,
          errorFallback: "That profile couldn't be loaded.",
          onRetry: () => ref.invalidate(profileProvider(userId)),
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: ShimmerScope(
              child: Column(
                children: [
                  ListRowSkeleton(leadingSize: 72),
                  SizedBox(height: AppSpacing.xl),
                  SkeletonBox(height: 96),
                ],
              ),
            ),
          ),
          data: (item) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            children: [
              ProfileHeader(profile: item, isSelf: isSelf),
              const SizedBox(height: AppSpacing.xl),
              if (!isSelf) ...[
                _FollowButton(userId: userId, name: item.displayName),
                const SizedBox(height: AppSpacing.xl),
              ],
              LifetimeStatsPanel(stats: item.stats),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(title: 'Recent walks'),
              RecentActivitiesStrip(userId: userId),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blocking, behind the affordance people already look for.
///
/// Not a button on the page. It is rare, it is about the person rather than
/// their walks, and putting it next to Follow would make a profile read as a
/// decision about whether somebody is safe — which is not the question most
/// people are answering when they open one.
///
/// There is deliberately no "Report this person" here. `moderation_reports`
/// takes an activity or a comment, and an admin acting on a report needs the
/// thing that was said; a report whose `target_id` was a profile would sit in
/// the queue as a broken row with no excerpt. Reporting stays on the walk and
/// the comment, where it works and where it means something. Blocking is the
/// control for "this person", and it takes effect without waiting for anybody.
class _ProfileOverflow extends ConsumerWidget {
  const _ProfileOverflow({required this.userId, required this.profile});

  final String userId;
  final AsyncValue<UserProfile> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = profile.value?.displayName ?? 'this member';
    final blocked = ref.watch(isBlockedProvider(userId)).value ?? false;

    return PopupMenuButton<_ProfileMenuAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) async {
        switch (action) {
          case _ProfileMenuAction.block:
            final nowBlocked = await confirmBlock(
              context,
              ref,
              otherId: userId,
              name: name,
            );
            // Blocking removes this profile from the viewer's reach entirely —
            // the restrictive policy on `profiles` stops the next read — so
            // staying on a screen that can no longer load would strand them on
            // an error. Leave with the block.
            if ((nowBlocked ?? false) && context.mounted) context.pop();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _ProfileMenuAction.block,
          child: Text(blocked ? 'Unblock $name' : 'Block $name'),
        ),
      ],
    );
  }
}

enum _ProfileMenuAction { block }

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(isFollowingProvider(userId));

    return OptimisticToggle(
      value: following.value ?? false,
      onToggle: () async {
        final nowFollowing = await ref
            .read(socialActionsProvider)
            .toggleFollow(userId);
        if (nowFollowing != null && context.mounted) {
          showAppSnackBar(
            context,
            nowFollowing ? 'Following $name.' : 'Unfollowed $name.',
          );
        }
        return nowFollowing;
      },
      onFailure: (error, stack) => reportFailure(
        context,
        error,
        stack,
        tag: 'PW-FOLLOW',
        fallback: "That didn't go through.",
      ),
      builder: (context, isFollowing, _, toggle) {
        if (isFollowing) {
          return SecondaryButton(
            label: 'Following',
            icon: Icons.check_rounded,
            expand: true,
            busy: following.isLoading,
            onPressed: toggle,
          );
        }
        return PrimaryButton(
          label: 'Follow',
          icon: Icons.add_rounded,
          expand: true,
          busy: following.isLoading,
          onPressed: toggle,
        );
      },
    );
  }
}
