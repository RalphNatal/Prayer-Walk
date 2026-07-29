import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/data/devotional_providers.dart';
import '../../devotionals/domain/devotional.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/bible_translation.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../../scripture/presentation/scripture_quotation.dart';
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

    final pending = ref.watch(pendingSubmissionCountProvider).value ?? 0;

    return AdminPage(
      title: 'Scripture prompts',
      subtitle: 'What gets spoken on a walk',
      showBack: true,
      actions: [
        // Badged rather than hidden behind a tab: a queue nobody sees is a
        // queue members are waiting in.
        Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          child: IconButton(
            tooltip: 'Member suggestions',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () =>
                context.goNamed(Routes.adminScriptureSubmissions),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.goNamed(Routes.adminScriptureCreate),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New prompt'),
      ),
      body: AsyncView<List<ScripturePrompt>>(
        value: prompts,
        errorFallback: "Scripture prompts couldn't be loaded.",
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
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _LicensingNote(),
                  _LicensedVerseCount(prompts: items),
                ],
              );
            }
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
              'WEBBE is public domain and needs no permission. The NLT may '
              'only be entered from a licensed source, within Tyndale’s limits '
              '— up to 500 verses, no complete book, and not more than 25% of '
              'the work. Do not paste NIV, ESV, NASB or CSB text here at all: '
              'this build carries no terms for them.',
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

/// How much of the licensed allowance has been used.
///
/// Curation drifts one verse at a time, and the 500-verse ceiling is the kind
/// of limit nobody notices crossing. Counted across both tables, because
/// Tyndale's limit is on the work rather than on one of its lists — a passage
/// quoted in a devotional spends the same allowance as one delivered on a walk.
///
/// The number is a floor, not a certificate: [approximateVerseCount] expands
/// `5:16-18` into three but reads a comma-separated or cross-chapter reference
/// as one. It exists so the drift is visible, not so the limit can be walked up
/// to precisely.
class _LicensedVerseCount extends ConsumerWidget {
  const _LicensedVerseCount({required this.prompts});

  final List<ScripturePrompt> prompts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Unresolved reads as an empty shelf rather than blocking the list: the
    // count is an aid on a screen that is about prompts.
    final devotionals =
        ref.watch(allDevotionalsProvider).value ?? const <Devotional>[];

    var counted = 0;
    for (final prompt in prompts) {
      if (prompt.translationInfo.requiresAttribution) {
        counted += approximateVerseCount(prompt.reference);
      }
    }
    for (final devotional in devotionals) {
      if (devotional.translationInfo.requiresAttribution) {
        counted += approximateVerseCount(devotional.scriptureRef);
      }
    }

    final configured = ref.watch(appTranslationProvider);
    // Nothing licensed anywhere and nothing configured to be: an app quoting
    // only public-domain text should not carry a licence meter.
    if (counted == 0 && !configured.requiresAttribution) {
      return const SizedBox.shrink();
    }

    final over = counted > kNltVerseCeiling;
    final tone = over ? theme.colorScheme.error : theme.colorScheme.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 18, color: tone),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Licensed verses: about $counted of $kNltVerseCeiling',
                  style: theme.textTheme.titleSmall?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            over
                ? 'Over the limit that may be quoted without express written '
                      'permission. Stop adding licensed verses and write to '
                      'permission@tyndale.com.'
                : 'Prompts and devotionals together, counting ranges. Above '
                      '500 verses — or any complete book — needs express '
                      'written permission from permission@tyndale.com.',
            style: theme.textTheme.bodySmall,
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
              // The console quotes the verse too, so it goes through the same
              // widget the walk does — an editor should see exactly what a
              // walker will, mark and all.
              ScriptureQuotation(
                text: prompt.body,
                translationId: prompt.translation,
                style: theme.textTheme.bodySmall,
                maxLines: 3,
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
                    StatusPill(
                      label: prompt.translationInfo.shortCode,
                      // A licensed edition reads as a caution rather than as
                      // one more neutral tag: it is the field on this row that
                      // carries an obligation.
                      tone: prompt.translationInfo.requiresAttribution
                          ? PillTone.warning
                          : PillTone.info,
                    ),
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
