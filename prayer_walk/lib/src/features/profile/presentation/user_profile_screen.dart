import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../social/data/mock_social_repository.dart';
import '../../social/data/social_actions.dart';
import '../data/mock_profile_repository.dart';
import '../domain/user_profile.dart';
import 'widgets/profile_pieces.dart';

/// Someone else's profile.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(profileProvider(userId).future),
        child: AsyncView<UserProfile>(
          value: profile,
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
              ProfileHeader(profile: item),
              const SizedBox(height: AppSpacing.xl),
              _FollowButton(userId: userId, name: item.displayName),
              const SizedBox(height: AppSpacing.xl),
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
    final isFollowing = following.value ?? false;

    Future<void> toggle() async {
      final nowFollowing = await ref
          .read(socialActionsProvider)
          .toggleFollow(userId);
      if (nowFollowing == null || !context.mounted) return;
      showAppSnackBar(
        context,
        nowFollowing ? 'Following $name.' : 'Unfollowed $name.',
      );
    }

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
  }
}
