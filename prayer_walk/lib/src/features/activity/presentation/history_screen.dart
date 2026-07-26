import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/mock_activity_repository.dart';
import '../domain/activity.dart';
import 'widgets/activity_pilgrimage_card.dart';

/// Everything you have walked, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activities = ref.watch(historyProvider);
    final filter = ref.watch(historyFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          _FilterBar(
            selected: filter,
            onSelect: (type) =>
                ref.read(historyFilterProvider.notifier).set(type),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(historyProvider.future),
              child: AsyncView<List<Activity>>(
                value: activities,
                onRetry: () => ref.invalidate(historyProvider),
                isEmpty: (items) => items.isEmpty,
                loading: const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.listBody,
                  child: CardListLoading(count: 2),
                ),
                empty: () => ScrollableStateBody(
                  child: EmptyState(
                    icon: Icons.route_outlined,
                    title: filter == null
                        ? 'No walks yet'
                        : 'No ${filter.label.toLowerCase()}s yet',
                    message: filter == null
                        ? 'Record your first walk and it will be waiting here.'
                        : 'Nothing recorded under this type. Clear the filter '
                              'to see everything.',
                    actionLabel: filter == null ? 'Record a walk' : 'Show all',
                    onAction: filter == null
                        ? () => context.goNamed(Routes.record)
                        : () => ref.read(historyFilterProvider.notifier).set(null),
                  ),
                ),
                data: (items) => ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.listBody,
                  itemCount: items.length + 1,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    if (index == 0) return _HistorySummary(activities: items);
                    return ActivityPilgrimageCard(
                      activity: items[index - 1],
                      isSelf: true,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});

  final ActivityType? selected;
  final ValueChanged<ActivityType?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        children: [
          ActivityTypeFilterChip(
            label: 'All',
            selected: selected == null,
            onSelected: () => onSelect(null),
          ),
          for (final type in ActivityType.values)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: ActivityTypeFilterChip(
                label: type.label,
                icon: ActivityTypeVisuals.icon(type),
                selected: selected == type,
                onSelected: () => onSelect(type),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of totals over whatever the filter is currently showing.
class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.activities});

  final List<Activity> activities;

  @override
  Widget build(BuildContext context) {
    final distance = activities.fold<double>(
      0,
      (sum, a) => sum + a.distanceMeters,
    );
    final time = activities.fold<Duration>(
      Duration.zero,
      (sum, a) => sum + a.duration,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        '${Fmt.plural(activities.length, 'walk')}  ·  '
        '${Fmt.distance(distance)}  ·  ${Fmt.durationShort(time)}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
