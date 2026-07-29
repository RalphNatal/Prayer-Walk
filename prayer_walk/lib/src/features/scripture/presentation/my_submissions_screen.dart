import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/scripture_providers.dart';
import '../domain/scripture_submission.dart';
import 'scripture_quotation.dart';

/// What a member sent, and what became of it.
///
/// Rejections appear here with their reason. A queue that swallows submissions
/// without saying so teaches people to stop sending them, and a parish that
/// stops contributing is a worse outcome than an awkward sentence.
class MySubmissionsScreen extends ConsumerWidget {
  const MySubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submissions = ref.watch(myScriptureSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your suggestions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(Routes.submitScripture),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Suggest one'),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(myScriptureSubmissionsProvider.future),
        child: AsyncView<List<ScriptureSubmission>>(
          value: submissions,
          errorFallback: "Your suggestions couldn't be loaded.",
          onRetry: () => ref.invalidate(myScriptureSubmissionsProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 3),
          ),
          empty: () => ScrollableStateBody(
            child: EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Nothing sent yet',
              message:
                  'A verse that carried you through something is worth passing '
                  'on. Suggest one and a moderator will read it.',
              actionLabel: 'Suggest a prompt',
              onAction: () => context.pushNamed(Routes.submitScripture),
            ),
          ),
          data: (items) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) =>
                _SubmissionRow(submission: items[index]),
          ),
        ),
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({required this.submission});

  final ScriptureSubmission submission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = submission.prompt;
    final rejected = submission.status == SubmissionStatus.rejected;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(prompt.reference, style: theme.textTheme.titleSmall),
              ),
              Text(
                submission.status.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: rejected
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (prompt.hasBody) ...[
            const SizedBox(height: AppSpacing.xs),
            ScriptureQuotation(
              text: prompt.body,
              translationId: prompt.translation,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
            ),
          ],
          if (submission.reflection.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(submission.reflection, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            submission.status.description,
            style: theme.textTheme.bodySmall,
          ),
          if (rejected && submission.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"${submission.rejectionReason}"',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (submission.submittedAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Sent ${Fmt.relativeTime(submission.submittedAt!)}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
