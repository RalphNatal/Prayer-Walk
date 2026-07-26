import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/recording_controller.dart';
import '../domain/activity.dart';
import 'trail_mapping.dart';

/// MOCK — real tracking arrives in Phase 3.
///
/// Nothing here is recording. The layout, the readouts and the controls are
/// the real thing so the flow can be walked end to end, but the route and the
/// numbers come from a pre-traced fixture handed over by the repository. The
/// banner says so on screen; when the location stream lands, this file changes
/// and the flow around it does not.
class LiveTrackingScreen extends ConsumerWidget {
  const LiveTrackingScreen({super.key});

  /// How much of the mock recording to show as "already walked".
  static const _progress = 0.62;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordingControllerProvider);
    final full = state.draft;

    if (full == null) {
      // Reached by deep link without a recording in flight.
      return Scaffold(
        appBar: AppBar(title: const Text('Live')),
        body: Center(
          child: EmptyState(
            icon: Icons.play_circle_outline_rounded,
            title: 'Nothing is recording',
            message: 'Start a walk and this screen will follow along.',
            actionLabel: 'Go to record',
            onAction: () => context.goNamed(Routes.record),
          ),
        ),
      );
    }

    final live = full.sliced(_progress);

    return PopScope(
      // Leaving mid-walk should be deliberate.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showConfirmDialog(
          context,
          title: 'Discard this walk?',
          message: 'Nothing has been saved yet. The route and the time go with it.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep walking',
          destructive: true,
        );
        if (!discard || !context.mounted) return;
        ref.read(recordingControllerProvider.notifier).reset();
        context.goNamed(Routes.record);
      },
      child: Scaffold(
        backgroundColor: AppColors.pine,
        body: Column(
          children: [
            const _MockBanner(),
            Expanded(
              flex: 5,
              child: RouteMapView(
                points: live.route,
                waypoints: live.waypoints.toTrailWaypoints(),
                pulsePoint: live.route.last,
                showEndpoints: false,
                showAttribution: false,
                interactive: false,
                semanticLabel:
                    'Map showing the route so far, '
                    '${Fmt.distance(live.distanceMeters)}',
              ),
            ),
            Expanded(
              flex: 4,
              child: _LivePanel(
                live: live,
                type: state.type,
                isPaused: state.isPaused,
                intentions: state.intentions,
                onTogglePause: () =>
                    ref.read(recordingControllerProvider.notifier).togglePause(),
                onFinish: () => context.goNamed(Routes.activitySummary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amber,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.construction_rounded,
                size: 18,
                color: AppColors.ink,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Simulated recording — no GPS is being read.',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.live,
    required this.type,
    required this.isPaused,
    required this.intentions,
    required this.onTogglePause,
    required this.onFinish,
  });

  final ActivityDraft live;
  final ActivityType type;
  final bool isPaused;
  final List<PrayerIntention> intentions;
  final VoidCallback onTogglePause;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onDark = AppColors.parchment;
    final muted = onDark.withValues(alpha: 0.72);

    final paceValue = type.usesSpeed
        ? Fmt.speed(live.distanceMeters, live.duration)
        : Fmt.pace(live.distanceMeters, live.duration);
    final paceLabel = type.usesSpeed ? 'km/h' : 'min/km';

    return Container(
      width: double.infinity,
      color: AppColors.pine,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isPaused)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'PAUSED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.amber,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              Text(
                Fmt.distanceValue(live.distanceMeters),
                style: AppTypography.statDisplay(onDark, size: 64),
              ),
              Text(
                '${Fmt.distanceUnit(live.distanceMeters)}  ·  ${type.label.toLowerCase()}',
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LiveStat(
                    label: 'Time',
                    value: Fmt.duration(live.duration),
                    onDark: onDark,
                    muted: muted,
                  ),
                  _LiveStat(
                    label: paceLabel,
                    value: paceValue,
                    onDark: onDark,
                    muted: muted,
                  ),
                  _LiveStat(
                    label: 'Elevation',
                    value: live.elevationGainMeters.round().toString(),
                    unit: 'm',
                    onDark: onDark,
                    muted: muted,
                  ),
                ],
              ),
              if (intentions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        intentions.first.text,
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTogglePause,
                      icon: Icon(
                        isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      label: Text(isPaused ? 'Resume' : 'Pause'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        foregroundColor: onDark,
                        side: BorderSide(color: onDark.withValues(alpha: 0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onFinish,
                      icon: const Icon(Icons.flag_rounded),
                      label: const Text('Finish'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                    ),
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

class _LiveStat extends StatelessWidget {
  const _LiveStat({
    required this.label,
    required this.value,
    required this.onDark,
    required this.muted,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final Color onDark;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value${unit ?? ''}',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTypography.statValue(onDark, size: 26)),
              if (unit != null)
                Text(
                  unit!,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
