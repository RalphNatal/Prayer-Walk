import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/devotional_providers.dart';
import '../domain/devotional.dart';

/// Browse the admin-curated shelf, grouped by category.
class DevotionalsScreen extends ConsumerWidget {
  const DevotionalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devotionals = ref.watch(publishedDevotionalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Devotionals')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(publishedDevotionalsProvider.future),
        child: AsyncView<List<Devotional>>(
          value: devotionals,
          errorFallback: "Devotionals couldn't be loaded.",
          onRetry: () => ref.invalidate(publishedDevotionalsProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            child: RowListLoading(count: 6, leadingSize: 56),
          ),
          empty: () => const ScrollableStateBody(
            child: EmptyState(
              icon: Icons.auto_stories_outlined,
              title: 'The shelf is empty',
              // An invitation, not an apology, and not a failure: the table is
              // there and nobody has published to it yet. The not-set-up state
              // in [ErrorStateView] is the one that means something is wrong.
              message:
                  'Nothing has been published yet. Check back after your '
                  'parish adds the first devotional.',
            ),
          ),
          data: (items) {
            final grouped = <DevotionalCategory, List<Devotional>>{};
            for (final devotional in items) {
              grouped.putIfAbsent(devotional.category, () => []).add(devotional);
            }
            final categories = DevotionalCategory.values
                .where(grouped.containsKey)
                .toList(growable: false);

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.listBody,
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: Text(
                      'Something to carry while you walk. '
                      '${Fmt.plural(items.length, 'prompt')} on the shelf.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final category = categories[index - 1];
                final entries = grouped[category]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        title: category.label,
                        subtitle: category.blurb,
                      ),
                      for (final devotional in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _DevotionalCard(devotional: devotional),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DevotionalCard extends StatelessWidget {
  const _DevotionalCard({required this.devotional});

  final Devotional devotional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.pushNamed(
          Routes.devotionalReader,
          pathParameters: {'devotionalId': devotional.id},
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: AppRadius.control,
                ),
                child: Icon(
                  devotional.hasScripture
                      ? Icons.menu_book_rounded
                      : Icons.wb_twilight_rounded,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(devotional.title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      devotional.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Text(
                          '${devotional.readMinutes} min read',
                          style: theme.textTheme.labelSmall,
                        ),
                        if (devotional.hasScripture) ...[
                          Text('  ·  ', style: theme.textTheme.labelSmall),
                          Flexible(
                            child: Text(
                              devotional.scriptureRef,
                              style: theme.textTheme.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
