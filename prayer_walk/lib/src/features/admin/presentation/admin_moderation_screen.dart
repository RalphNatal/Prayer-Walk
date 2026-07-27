import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/mock_admin_repository.dart';
import '../domain/admin_models.dart';
import 'widgets/status_pill.dart';

/// Reported activities and comments, oldest concern first.
class AdminModerationScreen extends ConsumerWidget {
  const AdminModerationScreen({super.key});

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    ModerationReport report,
    ReportStatus outcome,
  ) async {
    final isRemoval = outcome == ReportStatus.resolved;
    final confirmed = await showConfirmDialog(
      context,
      title: isRemoval ? 'Remove this content?' : 'Dismiss this report?',
      message: isRemoval
          ? 'The ${report.targetType.label.toLowerCase()} is taken down and '
                '${report.targetAuthorName} is notified.'
          : 'The content stays up and the report is closed.',
      confirmLabel: isRemoval ? 'Remove' : 'Dismiss',
      destructive: isRemoval,
    );
    if (!confirmed) return;

    await ref.read(adminRepositoryProvider).resolveReport(report.id, outcome);
    ref
      ..invalidate(moderationQueueProvider)
      ..invalidate(pendingReportCountProvider);
    if (context.mounted) {
      showAppSnackBar(
        context,
        isRemoval ? 'Content removed.' : 'Report dismissed.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(moderationQueueProvider);
    final filter = ref.watch(moderationFilterProvider);

    return AdminPage(
      title: 'Moderation',
      subtitle: 'Reported activities and comments',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _QueueFilter(
                    label: 'All',
                    selected: filter == null,
                    onSelected: () =>
                        ref.read(moderationFilterProvider.notifier).set(null),
                  ),
                  for (final status in ReportStatus.values)
                    _QueueFilter(
                      label: status.label,
                      selected: filter == status,
                      onSelected: () => ref
                          .read(moderationFilterProvider.notifier)
                          .set(status),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncView<List<ModerationReport>>(
              value: queue,
              onRetry: () => ref.invalidate(moderationQueueProvider),
              isEmpty: (items) => items.isEmpty,
              loading: const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: RowListLoading(count: 4, leadingSize: 44),
              ),
              empty: () => EmptyState(
                icon: Icons.verified_outlined,
                title: filter == ReportStatus.pending
                    ? 'Queue is clear'
                    : 'Nothing here',
                message: filter == ReportStatus.pending
                    ? 'No reports waiting. Check back after the weekend.'
                    : 'No reports with this status.',
              ),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => _ReportCard(
                  report: items[index],
                  onRemove: () => _resolve(
                    context,
                    ref,
                    items[index],
                    ReportStatus.resolved,
                  ),
                  onDismiss: () => _resolve(
                    context,
                    ref,
                    items[index],
                    ReportStatus.dismissed,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueFilter extends StatelessWidget {
  const _QueueFilter({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onRemove,
    required this.onDismiss,
  });

  final ModerationReport report;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = report.status == ReportStatus.pending;

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
          // `report.reason` is free text and can be long. Pills wrap onto a
          // second line rather than pushing the status off the card.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: report.targetType.label),
              StatusPill(
                label: report.reason,
                tone: PillTone.warning,
              ),
              StatusPill(
                label: report.status.label,
                tone: switch (report.status) {
                  ReportStatus.pending => PillTone.warning,
                  ReportStatus.resolved => PillTone.success,
                  ReportStatus.dismissed => PillTone.neutral,
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.control,
            ),
            child: Text(
              '"${report.targetExcerpt}"',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'By ${report.targetAuthorName}  ·  reported by '
            '${report.reportedByName}  ·  ${Fmt.relativeTime(report.createdAt)}',
            style: theme.textTheme.labelSmall,
          ),
          if (isPending) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SecondaryButton(label: 'Dismiss', onPressed: onDismiss),
                PrimaryButton(label: 'Remove content', onPressed: onRemove),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
