import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/widgets/widgets.dart';
import '../../groups/data/church_group_providers.dart';
import '../../groups/domain/church_group.dart';
import '../../groups/presentation/church_group_screen.dart' show GroupPromptCard;
import '../../groups/presentation/widgets/church_group_tile.dart';
import '../../groups/presentation/widgets/group_avatar.dart';
import '../../scripture/domain/scripture_prompt.dart';
import 'widgets/status_pill.dart';

const _tag = 'PW-MODERATION';

/// A reported church group, from the console's side.
///
/// The oversight half of groups: CALLED Presentations can see what a group is
/// and everything it has published, take a verse off members' walks, or remove
/// the group outright. Group content is user-generated, and the App Store's
/// rules for that (guideline 1.2) expect the app's operator to be able to act
/// on a report — which is the only reason the console looks inside a group at
/// all, and why this lives under Moderation rather than as a browsable list.
///
/// The policies grant exactly this: "Admins read all groups", "Admins remove
/// groups", and the existing "Admins manage prompts", which covers a group's
/// rows. Nothing here can edit a group's name or roster — that stays with the
/// group's own admins.
class AdminGroupReviewScreen extends ConsumerWidget {
  const AdminGroupReviewScreen({super.key, required this.groupId});

  final String groupId;

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ChurchGroup group,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove ${group.name}?',
      message:
          'The group is deleted for everyone, with its members list and every '
          "verse it shared, and its scripture stops arriving on members' "
          'walks. Members are not told why. This cannot be undone.',
      confirmLabel: 'Remove group',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(churchGroupRepositoryProvider).deleteGroup(group.id);
      if (!context.mounted) return;
      showAppSnackBar(context, '${group.name} was removed.');
      context.pop();
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The group wasn't removed.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(churchGroupProvider(groupId));
    final prompts = ref.watch(groupPromptsProvider(groupId));

    return AdminPage(
      title: group.value?.name ?? 'Church group',
      subtitle: 'Reported group',
      showBack: true,
      body: AsyncView<ChurchGroup>(
        value: group,
        errorFallback: "This group couldn't be loaded. It may already be gone.",
        onRetry: () => ref.invalidate(churchGroupProvider(groupId)),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 4),
        ),
        data: (loaded) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                ChurchGroupAvatar(group: loaded, outlined: false),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loaded.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (loaded.city.isNotEmpty) loaded.city,
                          memberCountLabel(loaded.memberCount),
                        ].join('  ·  '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                StatusPill(
                  label: loaded.isDiscoverable ? 'Listed' : 'Hidden',
                ),
                StatusPill(label: loaded.joinPolicy.label),
              ],
            ),
            if (loaded.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                loaded.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              title: 'What it has published',
              subtitle: "Switch one off to take it off members' walks.",
              dense: true,
            ),
            AsyncView<List<ScripturePrompt>>(
              value: prompts,
              errorFallback: "Its scripture couldn't be loaded.",
              onRetry: () => ref.invalidate(groupPromptsProvider(groupId)),
              isEmpty: (items) => items.isEmpty,
              loading: const RowListLoading(count: 2, leadingSize: 0),
              empty: () => const EmptyState(
                compact: true,
                icon: Icons.menu_book_outlined,
                title: 'Nothing published',
                message: 'This group has not shared any scripture.',
              ),
              data: (items) => Column(
                children: [
                  for (final prompt in items) ...[
                    _ReviewedPrompt(groupId: groupId, prompt: prompt),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                label: 'Remove this group',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onPressed: () => _remove(context, ref, loaded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewedPrompt extends ConsumerWidget {
  const _ReviewedPrompt({required this.groupId, required this.prompt});

  final String groupId;
  final ScripturePrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupPromptCard(prompt: prompt),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          title: Text(prompt.isPublished ? 'On walks' : 'Off walks'),
          value: prompt.isPublished,
          onChanged: (value) async {
            try {
              await ref
                  .read(churchGroupActionsProvider)
                  .setPromptPublished(groupId, prompt.id, published: value);
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
          },
        ),
      ],
    );
  }
}
