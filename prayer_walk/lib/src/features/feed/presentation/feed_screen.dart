import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../activity/presentation/widgets/activity_pilgrimage_card.dart';
import '../../auth/data/auth_providers.dart';
import '../../discovery/presentation/suggested_members_strip.dart';
import '../data/announcement_providers.dart';
import '../data/feed_providers.dart';
import '../domain/feed_entry.dart';

/// Home: walks from the people you follow, and your own — or, on the other
/// tab, walks from members who have chosen to share publicly.
///
/// Following is the default and stays the default. Explore is the door out of
/// an empty feed rather than the front page: a member's own parish comes first,
/// and a stream of strangers should be something they walk towards.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(feedTabProvider);
    final entries = ref.watch(
      tab == FeedTab.following ? feedProvider : exploreFeedProvider,
    );
    final viewerId = ref.watch(currentAuthUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Walk'),
        actions: [
          IconButton(
            tooltip: 'Find people',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => context.pushNamed(Routes.discover),
          ),
          IconButton(
            tooltip: 'Devotionals',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: () => context.goNamed(Routes.devotionals),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      // The banner and the tabs sit outside the RefreshIndicator so they are
      // present on the empty and loading states too — the first thing a brand
      // new member sees is an empty feed, which is exactly when a parish
      // announcement matters most, and exactly when the way out of it does.
      body: Column(
        children: [
          const _AnnouncementBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: SegmentedButton<FeedTab>(
              segments: const [
                ButtonSegment(
                  value: FeedTab.following,
                  label: Text('Following'),
                ),
                ButtonSegment(value: FeedTab.explore, label: Text('Explore')),
              ],
              selected: {tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ref.read(feedTabProvider.notifier).set(selection.first),
            ),
          ),
          Expanded(child: _feed(context, ref, theme, tab, entries, viewerId)),
        ],
      ),
    );
  }

  Widget _feed(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    FeedTab tab,
    AsyncValue<List<FeedEntry>> entries,
    String? viewerId,
  ) {
    final provider = tab == FeedTab.following
        ? feedProvider
        : exploreFeedProvider;

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(provider.future),
      child: AsyncView<List<FeedEntry>>(
        value: entries,
        errorFallback: tab == FeedTab.following
            ? "The feed couldn't be loaded."
            : "Explore couldn't be loaded.",
        onRetry: () => ref.invalidate(provider),
        isEmpty: (items) => items.isEmpty,
        loading: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.listBody,
          child: CardListLoading(),
        ),
        empty: () => tab == FeedTab.following
            ? const _EmptyFollowing()
            : const _EmptyExplore(),
        data: (items) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.listBody,
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  tab == FeedTab.following
                      ? _greeting(DateTime.now())
                      : 'Public walks from around the app',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final entry = items[index - 1];
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

/// A4 · The empty feed, which used to be a terminus.
///
/// A member who followed nobody and had walked nowhere saw an invitation to
/// record a walk and nothing else — no way to find a person, no way to see what
/// anyone else was doing, and every social feature in the app sitting one
/// unreachable step away. Three ways out now, and the strip of suggestions
/// above them is the shortest.
class _EmptyFollowing extends StatelessWidget {
  const _EmptyFollowing();

  @override
  Widget build(BuildContext context) {
    return ScrollableStateBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SuggestedMembersStrip(),
          ),
          EmptyState(
            icon: Icons.route_outlined,
            title: 'Your trail starts here',
            message:
                'Follow someone and their walks appear here. You can find '
                'people by name, look through public walks, or simply record '
                'your first.',
            actionLabel: 'Find people',
            onAction: () => context.pushNamed(Routes.discover),
            secondaryLabel: 'Record a walk',
            onSecondary: () => context.goNamed(Routes.record),
          ),
        ],
      ),
    );
  }
}

/// Explore with nothing in it means something specific, and it is not a
/// failure: nobody has yet chosen to make a walk public. Saying so — and saying
/// that it is a choice — is more useful than a shrug.
class _EmptyExplore extends StatelessWidget {
  const _EmptyExplore();

  @override
  Widget build(BuildContext context) {
    return ScrollableStateBody(
      child: EmptyState(
        icon: Icons.public_outlined,
        title: 'No public walks yet',
        message:
            'Walks are shared with followers by default. When someone chooses '
            'to make one public it turns up here — yours can be the first.',
        actionLabel: 'Record a walk',
        onAction: () => context.goNamed(Routes.record),
        secondaryLabel: 'Find people to follow',
        onSecondary: () => context.pushNamed(Routes.discover),
      ),
    );
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
