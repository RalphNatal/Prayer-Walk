import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/scripture_prompt.dart';
import 'scripture_quotation.dart';

/// The verse, set to be read.
///
/// Shared by the arrival card and the full reading so a passage looks like one
/// thing whether it is glanced at over the map or opened properly.
///
/// [showTranslation] governs the credit line under the text and nothing else.
/// The quotation itself is drawn by [ScriptureQuotation], which carries the
/// mark a licensed edition requires whatever the walker has switched off — a
/// preference may hide a courtesy, never a licence condition.
class ScriptureBody extends StatelessWidget {
  const ScriptureBody({
    super.key,
    required this.prompt,
    this.showTranslation = true,
    this.maxLines,
    this.onDark = false,
  });

  final ScripturePrompt prompt;
  final bool showTranslation;

  /// Null reads in full; a number truncates, for the card over the map.
  final int? maxLines;

  /// The card sits on a dark panel; the sheet on an ordinary surface.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = onDark ? AppColors.parchment : theme.colorScheme.onSurface;
    final muted = onDark
        ? AppColors.parchment.withValues(alpha: 0.72)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          prompt.reference,
          style: theme.textTheme.titleSmall?.copyWith(color: primary),
        ),
        const SizedBox(height: AppSpacing.xs),
        ScriptureQuotation(
          text: prompt.body,
          translationId: prompt.translation,
          maxLines: maxLines,
          style: theme.textTheme.bodyLarge?.copyWith(color: primary, height: 1.5),
        ),
        // The credit. Small, always present when there is an edition to name —
        // good practice for public-domain text, and shown alongside the full
        // notice in Settings for a licensed one.
        if (showTranslation && prompt.hasTranslation) ...[
          const SizedBox(height: AppSpacing.sm),
          TranslationCredit(
            translationId: prompt.translation,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

/// The whole passage, opened deliberately.
///
/// A sheet rather than a dialog, and dismissible by dragging or tapping away:
/// nothing on a walk should require an acknowledgement before the walker can
/// carry on looking at where they are going.
Future<void> showScriptureReading(
  BuildContext context,
  ScripturePrompt prompt, {
  bool showTranslation = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    prompt.kind == ScripturePromptKind.prayer
                        ? Icons.self_improvement_rounded
                        : Icons.menu_book_rounded,
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    prompt.kind.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ScriptureBody(prompt: prompt, showTranslation: showTranslation),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      );
    },
  );
}
