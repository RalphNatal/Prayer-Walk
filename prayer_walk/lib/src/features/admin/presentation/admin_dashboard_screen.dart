import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/domain/user_profile.dart';
import '../data/admin_providers.dart';
import '../domain/admin_models.dart';

/// The console's front page: four numbers, a trend, and who just arrived.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(adminMetricsProvider);

    return AdminPage(
      title: 'Dashboard',
      subtitle: 'Prayer Walk',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(adminMetricsProvider),
        ),
      ],
      body: AsyncView<AdminMetrics>(
        value: metrics,
        errorFallback: "The dashboard figures couldn't be loaded.",
        onRetry: () => ref.invalidate(adminMetricsProvider),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              children: [
                SkeletonBox(height: 96),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 200),
                SizedBox(height: AppSpacing.lg),
                RowListLoading(count: 3),
              ],
            ),
          ),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _MetricGrid(metrics: data),
            const SizedBox(height: AppSpacing.xl),
            _ActivityChart(series: data.activitySeries),
            const SizedBox(height: AppSpacing.xl),
            _RecentSignups(signups: data.recentSignups),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final AdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cards = <({String label, String value, IconData icon})>[
      (
        label: 'Total members',
        value: Fmt.count(metrics.totalMembers),
        icon: Icons.people_outline,
      ),
      (
        label: 'Active this week',
        value: Fmt.count(metrics.activeThisWeek),
        icon: Icons.bolt_outlined,
      ),
      (
        label: 'Activities logged',
        value: Fmt.count(metrics.activitiesLogged),
        icon: Icons.route_outlined,
      ),
      (
        label: 'Devotionals published',
        value: Fmt.count(metrics.devotionalsPublished),
        icon: Icons.auto_stories_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= AppBreakpoints.wide
            ? 4
            : constraints.maxWidth >= AppBreakpoints.compact
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: card.label,
                  value: card.value,
                  icon: card.icon,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: AppTypography.statValue(theme.colorScheme.onSurface, size: 28),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Activities over the last fortnight.
///
/// The series arrives from `admin_metrics` with every one of the fourteen days
/// present, zero-count days included. That is the point: a chart assembled only
/// from days that had walks redraws a quiet week as a busy one, which is the
/// one thing a dashboard must not do.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.series});

  final List<DailyCount> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = series.isEmpty
        ? 1
        : series.map((d) => d.count).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Activities over time',
            subtitle: 'Last 14 days',
            dense: true,
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
          ),
          SizedBox(
            height: 140,
            child: Semantics(
              label:
                  'Bar chart of activities logged over the last 14 days, '
                  'peaking at $peak in a day',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in series)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Fourteen bars across a phone leaves each a
                            // sliver; a three-digit day at a large text
                            // setting scales into its column.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                day.count.toString(),
                                maxLines: 1,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Container(
                              height: 96 * (day.count / peak),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.75,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(AppRadius.xs),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                series.isEmpty ? '' : Fmt.dayMonth(series.first.date),
                style: theme.textTheme.labelSmall,
              ),
              Text(
                series.isEmpty ? '' : Fmt.dayMonth(series.last.date),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSignups extends StatelessWidget {
  const _RecentSignups({required this.signups});

  final List<UserProfile> signups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Recent signups',
            dense: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            actionLabel: 'All members',
            onAction: () => context.goNamed(Routes.adminMembers),
          ),
          if (signups.isEmpty)
            Text('Nobody new this period.', style: theme.textTheme.bodySmall)
          else
            for (final person in signups) _SignupRow(person: person),
        ],
      ),
    );
  }
}

class _SignupRow extends StatelessWidget {
  const _SignupRow({required this.person});

  final UserProfile person;

  @override
  Widget build(BuildContext context) {
    // The card around this list paints its own background, which would hide the
    // tile's ink splash — so give the tile its own (transparent) Material to
    // splash on, rather than the decorated container above it.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: UserAvatar(
          initials: person.initials,
          accentIndex: person.accentIndex,
          size: AppSizes.avatarSm,
        ),
        title: Text(person.displayName),
        subtitle: Text('Joined ${Fmt.relativeTime(person.joinedAt)}'),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => context.goNamed(
          Routes.adminMemberDetail,
          pathParameters: {'memberId': person.id},
        ),
      ),
    );
  }
}
