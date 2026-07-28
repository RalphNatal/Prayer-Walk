import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../activity/presentation/widgets/activity_pilgrimage_card.dart';
import '../../auth/data/auth_providers.dart';
import '../data/announcement_providers.dart';
import '../data/feed_providers.dart';
import '../domain/feed_entry.dart';

/// Home: walks from the people you follow, and your own.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final feed = ref.watch(feedProvider);
    final viewerId = ref.watch(currentAuthUserIdProvider);

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
      // The banner sits outside the RefreshIndicator so it is present on the
      // empty and loading states too — the first thing a brand new member sees
      // is an empty feed, which is exactly when a parish announcement matters
      // most.
      body: Column(
        children: [
          const _AnnouncementBanner(),
          Expanded(child: _feed(context, ref, theme, feed, viewerId)),
        ],
      ),
    );
  }

  Widget _feed(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AsyncValue<List<FeedEntry>> feed,
    String? viewerId,
  ) {
    return RefreshIndicator(
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
    );
  }

  String _greeting(DateTime now) {
    if (now.hour < 11) return 'Walks from this morning';
    if (now.hour < 18) return 'Walks from today';
    return 'Walks from today and tonight';
  }
}

/// The most recent announcement addressed to this member, if there is one.
///
/// Deliberately one, and deliberately quiet: the feed belongs to the walks. The
/// full history is not a member-facing screen yet — what this fixes is the
/// worse problem, which was a table an admin wrote to that nobody could read.
///
/// It renders nothing at all while loading, on failure, or when there is
/// nothing addressed to this person. A parish broadcast is not worth a skeleton
/// or an error banner above someone's feed.
class _AnnouncementBanner extends ConsumerWidget {
  const _AnnouncementBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = ref.watch(memberAnnouncementsProvider).value?.firstOrNull;
    if (latest == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.campaign_outlined,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  latest.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            latest.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${latest.sentByName}  ·  ${Fmt.relativeTime(latest.sentAt)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
