import 'package:flutter/material.dart';

import '../../features/activity/domain/location_fix.dart' show LocationSignal;
import '../constants/app_spacing.dart';
import '../theme/app_colors.dart';

/// How sharp the GPS signal currently is, in a chip small enough to sit on a
/// map without competing with it.
///
/// This exists because of a specific failure mode: a position drawn at full
/// confidence while the accuracy radius is still two hundred metres looks like
/// a bug in the app rather than a GPS that hasn't locked. Naming the signal
/// converts "this is wrong" into "this isn't ready yet", which is usually the
/// truth and is always more useful.
class SignalIndicator extends StatelessWidget {
  const SignalIndicator({
    super.key,
    required this.signal,
    this.accuracyMeters,
    this.onDark = false,
  });

  final LocationSignal signal;

  /// Appended as `±24 m` when known. The radius is the actual claim; the word
  /// is only a summary of it.
  final double? accuracyMeters;

  /// Set on the live screen, whose panel and map sit on [AppColors.pine].
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final tint = switch (signal) {
      LocationSignal.sharp => AppColors.moss,
      LocationSignal.fair => AppColors.amber,
      LocationSignal.weak => scheme.error,
      LocationSignal.unknown => AppColors.stoneText,
    };

    final radius = accuracyMeters;
    final label = radius != null && radius > 0
        ? '${signal.label} · ±${radius.round()} m'
        : signal.label;

    final background = onDark
        ? Colors.black.withValues(alpha: 0.45)
        : scheme.surface.withValues(alpha: 0.9);
    final foreground = onDark ? AppColors.parchment : scheme.onSurface;

    return Semantics(
      label: 'Location signal: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.chip,
          border: Border.all(color: tint.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
