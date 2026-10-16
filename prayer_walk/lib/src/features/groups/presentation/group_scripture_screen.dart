import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../data/church_group_providers.dart';
import 'church_group_screen.dart' show GroupPromptCard;

const _tag = 'PW-GROUPS';

/// A group admin's scripture for their group: what is live, what is a draft,
/// and the way to add more.
///
/// This is the whole of a group admin's reach into scripture. It lists and
/// edits rows whose `group_id` is this group, and nothing else — not the
/// global library, not the submissions queue, not another group's verses. The
/// policies in `20261016020000_group_scripture.sql` are what make that true;
/// this screen only never asks for more.
class GroupScriptureScreen extends ConsumerWidget {
  const GroupScriptureScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(churchGroupProvider(groupId));
    final prompts = ref.watch(groupPromptsProvider(groupId));

    void compose() => context.pushNamed(
      Routes.churchGroupScriptureCompose,
      pathParameters: {'groupId': groupId},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Group scripture')),
      floatingActionButton: (group.value?.isAdmin ?? false)
          ? FloatingActionButton.extended(
              onPressed: compose,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Share scripture'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(groupPromptsProvider(groupId).future),
        child: AsyncView<List<ScripturePrompt>>(
          value: prompts,
          errorFallback: "This group's scripture couldn't be loaded.",
          onRetry: () => ref.invalidate(groupPromptsProvider(groupId)),
          isEmpty: (items) => items.isEmpty,
          loading: const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 4, leadingSize: 0),
          ),
          empty: () => ScrollableStateBody(
            child: EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Nothing shared yet',
              message:
                  'A verse or a prayer you share here reaches every member of '
                  '${group.value?.name ?? 'this group'} on their walks, '
                  "alongside the app's own library.",
              actionLabel: 'Share scripture',
              onAction: compose,
            ),
          ),
          data: (items) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            children: [
              Text(
                'Live items reach every member on their walks from their next '
                'sync. Drafts stay here.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final prompt in items) ...[
                _ManagedPrompt(groupId: groupId, prompt: prompt),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagedPrompt extends ConsumerWidget {
  const _ManagedPrompt({required this.groupId, required this.prompt});

  final String groupId;
  final ScripturePrompt prompt;

  Future<void> _togglePublished(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref
          .read(churchGroupActionsProvider)
          .setPromptPublished(groupId, prompt.id, published: value);
      if (context.mounted) {
        showAppSnackBar(
          context,
          value ? 'Live on members\' walks.' : 'Moved to drafts.',
        );
      }
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That didn't change.",
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${prompt.reference}"?',
      message:
          'It stops reaching members on their walks and is gone for good.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(churchGroupActionsProvider).deletePrompt(groupId, prompt.id);
      if (context.mounted) showAppSnackBar(context, 'Deleted.');
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That wasn't deleted.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupPromptCard(
          prompt: prompt,
          trailing: PopupMenuButton<String>(
            tooltip: 'More for ${prompt.reference}',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (choice) {
              if (choice == 'edit') {
                context.pushNamed(
                  Routes.churchGroupScriptureEdit,
                  pathParameters: {'groupId': groupId, 'promptId': prompt.id},
                );
              } else {
                _delete(context, ref);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
          ),
          title: Text(
            prompt.isPublished ? 'Live' : 'Draft',
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(
            prompt.isPublished
                ? 'Reaching members on their walks.'
                : 'Only admins of this group can see it.',
            style: theme.textTheme.bodySmall,
          ),
          value: prompt.isPublished,
          onChanged: (value) => _togglePublished(context, ref, value),
        ),
      ],
    );
  }
}
