import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/data/devotional_providers.dart';
import '../../devotionals/domain/devotional.dart';
import '../data/admin_providers.dart';
import 'widgets/status_pill.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ADMINCONTENT';

/// Devotionals: what is live, what is still a draft.
///
/// Scripture prompts — the in-motion counterpart, read on a walk rather than
/// sitting down — are managed on their own screen, one tap from the top of this
/// list. They are different enough in shape (a reference and one breath of
/// text, versus a title, summary and reader body) that sharing a form would
/// have made both worse.
class AdminContentScreen extends ConsumerWidget {
  const AdminContentScreen({super.key});

  Future<void> _togglePublish(
    BuildContext context,
    WidgetRef ref,
    Devotional item,
  ) async {
    final publish = !item.isPublished;
    if (!publish) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Unpublish "${item.title}"?',
        message: 'Members stop seeing it on the devotionals shelf immediately.',
        confirmLabel: 'Unpublish',
        destructive: true,
      );
      if (!confirmed) return;
    }

    try {
      await ref
          .read(devotionalRepositoryProvider)
          .setPublished(item.id, published: publish);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "\"${item.title}\" didn't change.",
        );
      }
      return;
    }
    _refresh(ref);
    if (context.mounted) {
      showAppSnackBar(
        context,
        publish ? '"${item.title}" published.' : '"${item.title}" unpublished.',
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Devotional item,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${item.title}"?',
      message: 'The text is removed for everyone. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(devotionalRepositoryProvider).delete(item.id);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "\"${item.title}\" wasn't deleted.",
        );
      }
      return;
    }
    _refresh(ref);
    if (context.mounted) {
      showAppSnackBar(context, '"${item.title}" deleted.');
    }
  }

  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(allDevotionalsProvider)
      ..invalidate(publishedDevotionalsProvider)
      ..invalidate(adminMetricsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devotionals = ref.watch(allDevotionalsProvider);

    return AdminPage(
      title: 'Content',
      subtitle: 'Devotionals and prayer prompts',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.goNamed(Routes.adminContentCreate),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New devotional'),
      ),
      body: AsyncView<List<Devotional>>(
        value: devotionals,
        onRetry: () => ref.invalidate(allDevotionalsProvider),
        isEmpty: (items) => items.isEmpty,
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 5, leadingSize: 48),
        ),
        empty: () => Column(
          children: [
            const _ScriptureLink(),
            Expanded(
              child: EmptyState(
                icon: Icons.article_outlined,
                title: 'No devotionals yet',
                message: 'Write the first one and publish it to the shelf.',
                actionLabel: 'New devotional',
                onAction: () => context.goNamed(Routes.adminContentCreate),
              ),
            ),
          ],
        ),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl * 2,
          ),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            if (index == 0) return const _ScriptureLink();
            final item = items[index - 1];
            return _ContentRow(
              devotional: item,
              onEdit: () => context.goNamed(
                Routes.adminContentEdit,
                pathParameters: {'devotionalId': item.id},
              ),
              onTogglePublish: () => _togglePublish(context, ref, item),
              onDelete: () => _delete(context, ref, item),
            );
          },
        ),
      ),
    );
  }
}

/// The way through to the other half of the curated library.
class _ScriptureLink extends StatelessWidget {
  const _ScriptureLink();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.control,
        child: InkWell(
          borderRadius: AppRadius.control,
          onTap: () => context.goNamed(Routes.adminScripture),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scripture prompts',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        'The verses and short prayers delivered on a walk.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentRow extends StatelessWidget {
  const _ContentRow({
    required this.devotional,
    required this.onEdit,
    required this.onTogglePublish,
    required this.onDelete,
  });

  final Devotional devotional;
  final VoidCallback onEdit;
  final VoidCallback onTogglePublish;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          devotional.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          devotional.summary,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  StatusPill(
                    label: devotional.isPublished ? 'Published' : 'Draft',
                    tone: devotional.isPublished
                        ? PillTone.success
                        : PillTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(label: devotional.category.label),
                  Text(
                    '${devotional.authorName}  ·  updated '
                    '${Fmt.relativeTime(devotional.updatedAt)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Three labelled buttons do not fit one line on a phone at a
              // large text setting. They wrap to a second line rather than
              // running off the card — and Delete stays last either way.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.start,
                children: [
                  AppTextButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                  AppTextButton(
                    label: devotional.isPublished ? 'Unpublish' : 'Publish',
                    icon: devotional.isPublished
                        ? Icons.visibility_off_outlined
                        : Icons.publish_rounded,
                    onPressed: onTogglePublish,
                  ),
                  AppTextButton(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
