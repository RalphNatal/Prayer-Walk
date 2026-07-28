import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/scripture_prompt.dart';
import 'widgets/status_pill.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ADMINSCRIPTURE';

/// Curate what gets spoken on a walk.
///
/// Until now this table had no interface at all: the seed file was the only way
/// to add or retire a verse, which meant curating the library required database
/// access. Everything the seed does by hand, this screen does in the app.
class AdminScriptureScreen extends ConsumerWidget {
  const AdminScriptureScreen({super.key});

  Future<void> _togglePublish(
    BuildContext context,
    WidgetRef ref,
    ScripturePrompt prompt,
  ) async {
    final publish = !prompt.isPublished;
    if (!publish) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Unpublish "${prompt.reference}"?',
        message:
            'It stops being delivered on walks. Anyone already carrying a '
            'synced copy keeps it until their next sync.',
        confirmLabel: 'Unpublish',
        destructive: true,
      );
      if (!confirmed) return;
    }

    try {
      await ref
          .read(scriptureRepositoryProvider)
          .setPublished(prompt.id, published: publish);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That prompt didn't change.",
        );
      }
      return;
    }
    _refresh(ref);
    if (context.mounted) {
      showAppSnackBar(
        context,
        publish
            ? '"${prompt.reference}" is live on walks.'
            : '"${prompt.reference}" unpublished.',
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ScripturePrompt prompt,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${prompt.reference}"?',
      message:
          'The text is removed from the library for everyone. This cannot be '
          'undone — unpublish instead if you may want it back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(scriptureRepositoryProvider).deletePrompt(prompt.id);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That prompt wasn't deleted.",
        );
      }
      return;
    }
    _refresh(ref);
    if (context.mounted) {
      showAppSnackBar(context, '"${prompt.reference}" deleted.');
    }
  }

  /// The walk's own copy of the library is warmed once per app run and has to
  /// be told it moved, or a newly published verse waits for a restart.
  void _refresh(WidgetRef ref) {
    ref
      ..invalidate(allScripturePromptsProvider)
      ..invalidate(scriptureLibraryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompts = ref.watch(allScripturePromptsProvider);

    return AdminPage(
      title: 'Scripture prompts',
      subtitle: 'What gets spoken on a walk',
      showBack: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.goNamed(Routes.adminScriptureCreate),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New prompt'),
      ),
      body: AsyncView<List<ScripturePrompt>>(
        value: prompts,
        onRetry: () => ref.invalidate(allScripturePromptsProvider),
        isEmpty: (items) => items.isEmpty,
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 6, leadingSize: 44),
        ),
        empty: () => EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No prompts yet',
          message:
              'Nothing will be delivered on a walk until there is something '
              'here. Add the first, or run the seed file.',
          actionLabel: 'New prompt',
          onAction: () => context.goNamed(Routes.adminScriptureCreate),
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
            if (index == 0) return const _LicensingNote();
            final prompt = items[index - 1];
            return _PromptRow(
              prompt: prompt,
              onEdit: () => context.goNamed(
                Routes.adminScriptureEdit,
                pathParameters: {'promptId': prompt.id},
              ),
              onTogglePublish: () => _togglePublish(context, ref, prompt),
              onDelete: () => _delete(context, ref, prompt),
            );
          },
        ),
      ),
    );
  }
}

/// Stated once at the top of the list, not buried in a help page. It is the one
/// rule an editor here can break in a way that costs money.
class _LicensingNote extends StatelessWidget {
  const _LicensingNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.balance_outlined,
            size: 20,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Public-domain text only. WEBBE is the default and needs no '
              'permission. Do not paste NIV, ESV, NLT, NASB or CSB text here — '
              'those are licensed, and redistributing them in an app is not '
              'covered by fair use.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.prompt,
    required this.onEdit,
    required this.onTogglePublish,
    required this.onDelete,
  });

  final ScripturePrompt prompt;
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
                    child: Text(
                      prompt.reference,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  StatusPill(
                    label: prompt.isPublished ? 'Published' : 'Draft',
                    tone: prompt.isPublished
                        ? PillTone.success
                        : PillTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                prompt.body,
                style: theme.textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(label: prompt.kind.label),
                  StatusPill(label: prompt.category.label),
                  if (prompt.hasTranslation)
                    StatusPill(label: prompt.translation, tone: PillTone.info),
                  Text(
                    'order ${prompt.sortOrder}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  AppTextButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                  AppTextButton(
                    label: prompt.isPublished ? 'Unpublish' : 'Publish',
                    icon: prompt.isPublished
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
