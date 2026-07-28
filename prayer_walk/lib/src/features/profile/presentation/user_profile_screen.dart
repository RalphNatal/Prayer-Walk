import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
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
      appBar: AppBar(title: const Text('Profile')),
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
