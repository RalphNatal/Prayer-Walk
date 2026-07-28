import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../admin/domain/admin_models.dart' show ReportTargetType;
import '../data/supabase_report_repository.dart';

/// Log tag for reporting failures.
const _tag = 'PW-REPORT';

/// The reasons offered, in the order a person is likely to want them.
///
/// Free text is allowed underneath but never required: making somebody
/// articulate why something upset them before they can flag it is a good way to
/// get nothing flagged.
const _reasons = <String>[
  'Unkind or hostile',
  'Not appropriate here',
  'Spam or advertising',
  'Something else',
];

/// Ask why, file it, say thank you quietly.
///
/// The copy here is deliberately flat. Reporting is a small administrative act,
/// not an accusation, and a sheet that reads like a tribunal makes people either
/// avoid it or over-use it.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required ReportTargetType targetType,
  required String targetId,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ReportSheet(targetType: targetType),
  );
  if (reason == null || !context.mounted) return;

  try {
    await ref
        .read(reportRepositoryProvider)
        .report(targetType: targetType, targetId: targetId, reason: reason);
  } catch (error, stack) {
    if (context.mounted) {
      reportFailure(
        context,
        error,
        stack,
        tag: _tag,
        fallback: "That report didn't send.",
      );
    }
    return;
  }
  if (context.mounted) {
    showAppSnackBar(context, 'Thanks — an admin will take a look.');
  }
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetType});

  final ReportTargetType targetType;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  String _reason = _reasons.first;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The chosen reason, with the note appended when there is one. One column on
  /// the table, because the queue reads it as one line.
  String get _combined {
    final note = _note.text.trim();
    return note.isEmpty ? _reason : '$_reason — $note';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.targetType.label.toLowerCase();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report this $target', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This goes to an admin. Nobody else sees that you reported it, '
              'and nothing happens to the $target automatically.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value ?? _reason),
              child: Column(
                children: [
                  for (final reason in _reasons)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: reason,
                      title: Text(reason),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anything to add? (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            PrimaryButton(
              label: 'Send report',
              expand: true,
              large: true,
              onPressed: () => Navigator.of(context).pop(_combined),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: AppTextButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
