import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../activity/presentation/widgets/activity_pilgrimage_card.dart';
import '../../auth/data/auth_providers.dart';
import '../data/mock_feed_repository.dart';
import '../domain/feed_entry.dart';

/// Home: walks from the people you follow, and your own.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final feed = ref.watch(feedProvider);
    final viewerId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Walk'),
        actions: [
          IconButton(
            tooltip: 'Devotionals',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => context.goNamed(Routes.devotionals),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(feedProvider.future),
        child: AsyncView<List<FeedEntry>>(
          value: feed,
          onRetry: () => ref.invalidate(feedProvider),
          isEmpty: (entries) => entries.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            child: CardListLoading(),
          ),
          empty: () => ScrollableStateBody(
            child: EmptyState(
              icon: Icons.route_outlined,
              title: 'Your trail starts here',
              message:
                  'Follow someone, or record your first walk. Whatever you '
                  'log will show up here.',
              actionLabel: 'Record a walk',
              onAction: () => context.goNamed(Routes.record),
            ),
          ),
          data: (entries) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    _greeting(DateTime.now()),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final entry = entries[index - 1];
              return ActivityPilgrimageCard(
                activity: entry.activity,
                author: entry.author,
                isSelf: entry.author.id == viewerId,
              );
            },
          ),
        ),
      ),
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 11) return 'Walks from this morning';
    if (now.hour < 18) return 'Walks from today';
    return 'Walks from today and tonight';
  }
}
