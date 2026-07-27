import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/profile_providers.dart';
import '../domain/user_profile.dart';
import 'widgets/profile_pieces.dart';

/// Your profile: who you are here, what you have walked, and the way out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.pushNamed(Routes.settings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(currentProfileProvider.future),
        child: AsyncView<UserProfile>(
          value: profile,
          onRetry: () => ref.invalidate(currentProfileProvider),
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: ShimmerScope(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListRowSkeleton(leadingSize: 72),
                  SizedBox(height: AppSpacing.xl),
                  SkeletonBox(height: 96),
                  SizedBox(height: AppSpacing.xl),
                  SkeletonBox(height: 168),
                ],
              ),
            ),
          ),
          data: (item) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            children: [
              ProfileHeader(profile: item, isSelf: true),
              const SizedBox(height: AppSpacing.xl),
              LifetimeStatsPanel(stats: item.stats),
              const SizedBox(height: AppSpacing.xl),

              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Edit profile',
                      icon: Icons.edit_outlined,
                      expand: true,
                      onPressed: () => context.pushNamed(Routes.editProfile),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SecondaryButton(
                      label: 'Settings',
                      icon: Icons.settings_outlined,
                      expand: true,
                      onPressed: () => context.pushNamed(Routes.settings),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),
              SectionHeader(
                title: 'Recent walks',
                actionLabel: 'See all',
                onAction: () => context.goNamed(Routes.history),
              ),
              RecentActivitiesStrip(userId: item.id),
            ],
          ),
        ),
      ),
    );
  }
}
