import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/data/devotional_providers.dart';
import '../../devotionals/domain/devotional.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/bible_translation.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../../scripture/domain/scripture_submission.dart';
import '../../scripture/presentation/scripture_quotation.dart';
import 'widgets/status_pill.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-SUBMISSIONS';

/// C1/C2 · What members have proposed, and the two decisions about it.
///
/// Reuses the moderation queue's shape on purpose — filter chips, a card per
/// item, uphold-or-dismiss — because approving a submission and closing a
/// report are the same administrative act from the same seat, and an admin
/// should not have to learn a second one.
///
/// ⚖️ The verse counter above the list is not decoration. Tyndale's ceiling is
/// 500 NLT verses without written permission, and the shape of a queue is that
/// it is worked through quickly. This is the screen where the limit can be
/// crossed one approval at a time by somebody who is being helpful, so the
/// number is on screen before any decision is made, and an approval that would
/// cross it has to be confirmed against a dialog that says so.
class AdminScriptureSubmissionsScreen extends ConsumerWidget {
  const AdminScriptureSubmissionsScreen({super.key});

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    ScriptureSubmission submission,
    int countedNow,
  ) async {
    final cost = submission.licensedVerseCost;
    final after = countedNow + cost;
    final crosses = cost > 0 && after > kNltVerseCeiling;

    final confirmed = await showConfirmDialog(
      context,
      title: crosses
          ? 'This would pass the licence limit'
          : 'Approve "${submission.prompt.reference}"?',
      message: crosses
          // Loud, and specific about what it costs. An admin approving past the
          // ceiling should have to read a number, not dismiss a shrug.
          ? 'Approving this takes the app to about $after licensed verses, '
                'over the $kNltVerseCeiling that may be quoted without express '
                'written permission from Tyndale. Do not approve further '
                'licensed text until permission@tyndale.com has confirmed '
                'permission in writing.'
          : 'It is published and starts being delivered on walks, credited to '
                '${submission.contributorName}'
                '${cost > 0 ? ' — and spends about $cost of the '
                      '$kNltVerseCeiling licensed verses' : ''}.',
      confirmLabel: crosses ? 'Approve anyway' : 'Approve',
      destructive: crosses,
    );
    if (!confirmed || !context.mounted) return;

    await _review(
      context,
      ref,
      submission,
      SubmissionStatus.approved,
      done: '"${submission.prompt.reference}" is live on walks.',
    );
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    ScriptureSubmission submission,
  ) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RejectSheet(submission: submission),
    );
    if (reason == null || !context.mounted) return;

    await _review(
      context,
      ref,
      submission,
      SubmissionStatus.rejected,
      reason: reason,
      done: 'Not used. ${submission.contributorName} will see your reason.',
    );
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    ScriptureSubmission submission,
    SubmissionStatus outcome, {
    String reason = '',
    required String done,
  }) async {
    try {
      await ref
          .read(scriptureRepositoryProvider)
          .reviewSubmission(
            submission.prompt.id,
            outcome: outcome,
            reason: reason,
          );
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That decision wasn't recorded.",
        );
      }
      return;
    }
    ref
      ..invalidate(scriptureSubmissionsProvider)
      ..invalidate(pendingSubmissionCountProvider)
      ..invalidate(allScripturePromptsProvider)
      // The walk's own copy of the library is warmed once per app run and has
      // to be told it moved, or a newly approved verse waits for a restart.
      ..invalidate(scriptureLibraryProvider);
    if (context.mounted) showAppSnackBar(context, done);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(scriptureSubmissionsProvider);
    final filter = ref.watch(submissionFilterProvider);
    final counted = ref.watch(_licensedVerseCountProvider);

    return AdminPage(
      title: 'Member suggestions',
      subtitle: 'Proposed prompts, waiting on a decision',
      showBack: true,
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
                        ref.read(submissionFilterProvider.notifier).set(null),
                  ),
                  for (final status in SubmissionStatus.values)
                    _QueueFilter(
                      label: status.label,
                      selected: filter == status,
                      onSelected: () => ref
                          .read(submissionFilterProvider.notifier)
                          .set(status),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncView<List<ScriptureSubmission>>(
              value: queue,
              errorFallback: "The suggestions queue couldn't be loaded.",
              onRetry: () => ref.invalidate(scriptureSubmissionsProvider),
              isEmpty: (items) => items.isEmpty,
              loading: const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: RowListLoading(count: 4, leadingSize: 44),
              ),
              empty: () => EmptyState(
                icon: Icons.verified_outlined,
                title: filter == SubmissionStatus.pending
                    ? 'Nothing waiting'
                    : 'Nothing here',
                message: filter == SubmissionStatus.pending
                    ? 'No suggestions to read. Members can send one from the '
                          'app at any time.'
                    : 'No suggestions with this status.',
              ),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  if (index == 0) return _VerseCeilingMeter(counted: counted);
                  final submission = items[index - 1];
                  return _SubmissionCard(
                    submission: submission,
                    onApprove: () =>
                        _approve(context, ref, submission, counted),
                    onReject: () => _reject(context, ref, submission),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ⚖️ How many licensed verses the app is currently quoting, counted across
/// both tables.
///
/// Tyndale's limit is on the work rather than on one of its lists — a passage
/// quoted in a devotional spends the same allowance as one delivered on a walk
/// — so both are counted. The number is a floor, not a certificate:
/// [approximateVerseCount] expands `5:16-18` into three but reads a
/// comma-separated or cross-chapter reference as one.
///
/// A failed read of either list contributes zero rather than blocking the
/// queue. That under-counts, which is the wrong direction for a limit — so the
/// meter says when it could not see everything rather than presenting a partial
/// count as the whole.
final _licensedVerseCountProvider = Provider<int>((ref) {
  final prompts =
      ref.watch(allScripturePromptsProvider).value ??
      const <ScripturePrompt>[];
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
  return counted;
});

class _VerseCeilingMeter extends ConsumerWidget {
  const _VerseCeilingMeter({required this.counted});

  final int counted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final partial =
        ref.watch(allScripturePromptsProvider).hasValue == false ||
        ref.watch(allDevotionalsProvider).hasValue == false;

    final over = counted > kNltVerseCeiling;
    final near = !over && counted > kNltVerseCeiling * 0.8;
    final tone = over
        ? theme.colorScheme.error
        : near
        ? theme.colorScheme.tertiary
        : theme.colorScheme.outline;

    return Container(
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
              Icon(Icons.balance_outlined, size: 18, color: tone),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Licensed verses: about $counted of $kNltVerseCeiling',
                  style: theme.textTheme.titleSmall?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: (counted / kNltVerseCeiling).clamp(0.0, 1.0),
              minHeight: 6,
              color: tone,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            over
                ? 'Over the limit that may be quoted without express written '
                      'permission. Do not approve further licensed text — '
                      'write to permission@tyndale.com.'
                : 'Prompts and devotionals together, counting ranges. Member '
                      'suggestions are public-domain only and cost nothing '
                      'against this; only text an admin has set to a licensed '
                      'edition does.',
            style: theme.textTheme.bodySmall,
          ),
          if (partial) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'One of the two lists has not loaded, so this is an undercount. '
              'Reload before approving anything licensed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
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

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.submission,
    required this.onApprove,
    required this.onReject,
  });

  final ScriptureSubmission submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = submission.prompt;
    final pending = submission.status == SubmissionStatus.pending;
    final licensed = prompt.translationInfo.requiresAttribution;

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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: prompt.kind.label),
              StatusPill(label: prompt.category.label),
              // ⚖️ The translation is on the card, not behind an edit screen.
              // It is the field that decides whether approving this costs
              // anything against the ceiling, and an admin should not have to
              // open a form to find out.
              StatusPill(
                label: prompt.hasTranslation
                    ? prompt.translationInfo.shortCode
                    : 'No quotation',
                tone: licensed ? PillTone.warning : PillTone.info,
              ),
              if (licensed)
                StatusPill(
                  label: 'costs ~${submission.licensedVerseCost} verses',
                  tone: PillTone.warning,
                ),
              StatusPill(
                label: submission.status.label,
                tone: switch (submission.status) {
                  SubmissionStatus.pending => PillTone.warning,
                  SubmissionStatus.approved => PillTone.success,
                  SubmissionStatus.rejected => PillTone.neutral,
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(prompt.reference, style: theme.textTheme.titleSmall),
          if (prompt.hasBody) ...[
            const SizedBox(height: AppSpacing.xs),
            // The console quotes it through the same widget a walk does, so an
            // admin sees exactly what a walker will — mark and all.
            ScriptureQuotation(
              text: prompt.body,
              translationId: prompt.translation,
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No text sent — the reference alone. Match it to something the '
              'library already holds before publishing.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (submission.reflection.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.control,
              ),
              child: Text(
                submission.reflection,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'From ${submission.contributorName}'
            '${submission.submittedAt == null ? '' : '  ·  ${Fmt.relativeTime(submission.submittedAt!)}'}',
            style: theme.textTheme.labelSmall,
          ),
          if (pending) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SecondaryButton(label: 'Not this one', onPressed: onReject),
                PrimaryButton(label: 'Approve', onPressed: onApprove),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Why not. Free text, and required — a rejection with no reason is what makes
/// somebody stop contributing.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.submission});

  final ScriptureSubmission submission;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Not using this one',
            subtitle:
                '${widget.submission.contributorName} will see what you write. '
                'A sentence is enough.',
          ),
          TextField(
            controller: _reason,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'We already have this passage in the library.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Send decision',
            expand: true,
            onPressed: () {
              final reason = _reason.text.trim();
              if (reason.isEmpty) {
                showAppSnackBar(context, 'Give them a reason first.');
                return;
              }
              Navigator.of(context).pop(reason);
            },
          ),
        ],
      ),
    );
  }
}
