import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../social/data/social_providers.dart';
import '../domain/user_profile.dart';

enum FollowListMode {
  followers('Followers', 'No followers yet', 'Walk, and people will find you.'),
  following(
    'Following',
    'Not following anyone yet',
    'Find someone from your parish and follow their walks.',
  );

  const FollowListMode(this.title, this.emptyTitle, this.emptyMessage);

  final String title;
  final String emptyTitle;
  final String emptyMessage;
}

/// Followers or following, for any profile.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  final String userId;
  final FollowListMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mode == FollowListMode.followers
        ? followersProvider(userId)
        : followingProvider(userId);
    final people = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: Text(mode.title)),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(provider.future),
        child: AsyncView<List<UserProfile>>(
          value: people,
          onRetry: () => ref.invalidate(provider),
          isEmpty: (items) => items.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 5),
          ),
          empty: () => ScrollableStateBody(
            child: EmptyState(
              icon: Icons.people_outline,
              title: mode.emptyTitle,
              message: mode.emptyMessage,
            ),
          ),
          data: (items) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final person = items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                ),
                leading: UserAvatar(
                  initials: person.initials,
                  accentIndex: person.accentIndex,
                ),
                title: Text(person.displayName),
                subtitle: Text(
                  person.parish.isEmpty ? person.handle : person.parish,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed(
                  Routes.userProfile,
                  pathParameters: {'userId': person.id},
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
