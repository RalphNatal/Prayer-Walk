import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';

enum PillTone { neutral, success, warning, danger, info }

/// A compact status marker for admin rows: published, suspended, pending.
///
/// Tone is carried by colour *and* by the word, never by colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final (background, foreground) = switch (tone) {
      PillTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
      PillTone.success => (
        theme.colorScheme.secondaryContainer,
        isLight ? AppColors.verdantLight : AppColors.verdantDark,
      ),
      PillTone.warning => (
        theme.colorScheme.tertiaryContainer,
        isLight ? AppColors.ochreLight : AppColors.ochreDark,
      ),
      PillTone.danger => (
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
      PillTone.info => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
