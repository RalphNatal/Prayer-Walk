import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/admin_providers.dart';
import '../domain/admin_models.dart';
import 'widgets/status_pill.dart';

/// Everything that has been broadcast, newest first.
class AdminAnnouncementsScreen extends ConsumerWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcements = ref.watch(announcementsProvider);

    return AdminPage(
      title: 'Announcements',
      subtitle: 'Broadcasts to members',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.goNamed(Routes.adminAnnouncementCompose),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose'),
      ),
      body: AsyncView<List<Announcement>>(
        value: announcements,
        errorFallback: "Announcements couldn't be loaded.",
        onRetry: () => ref.invalidate(announcementsProvider),
        isEmpty: (items) => items.isEmpty,
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 3, leadingSize: 44),
        ),
        empty: () => EmptyState(
          icon: Icons.campaign_outlined,
          title: 'Nothing sent yet',
          message: 'Compose the first announcement to your members.',
          actionLabel: 'Compose',
          onAction: () => context.goNamed(Routes.adminAnnouncementCompose),
        ),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl * 2,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) =>
              _AnnouncementCard(announcement: items[index]),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  announcement.title,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              StatusPill(
                label: announcement.audience.label,
                tone: PillTone.info,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(announcement.body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sent by ${announcement.sentByName}  ·  '
            '${Fmt.dayMonthYear(announcement.sentAt)}  ·  '
            '${Fmt.plural(announcement.recipientCount, 'recipient')}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
