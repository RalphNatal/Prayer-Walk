import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/scripture_settings.dart';
import '../../scripture/presentation/scripture_arrival_card.dart';
import '../../scripture/presentation/scripture_reading.dart';
import '../data/recording_controller.dart';
import '../domain/activity.dart';
import 'trail_mapping.dart';

/// The walk as it happens: the trail drawing itself, the numbers moving, and —
/// when scripture is on — a verse arriving now and then.
///
/// Everything here reads [RecordingController]'s live state: the route, the
/// distance, the clock and the verses are all being accumulated by the
/// recorder. The screen owns no recording logic of its own. What it does own is
/// the *announcement* — the chime, the haptic and the voice — because those are
/// platform channels, and keeping them out of the controller is what lets the
/// recorder be tested without a speaker.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  /// Whether the one-time "your phone has no step sensor" note has been shown.
  bool _toldAboutFallback = false;

  /// Held in a field rather than read on demand: `dispose` needs it, and `ref`
  /// is not safe to touch once the element is on its way out.
  late final ScriptureAnnouncer _announcer;

  @override
  void initState() {
    super.initState();
    _announcer = ref.read(scriptureAnnouncerProvider);
  }

  @override
  void dispose() {
    // Leaving the screen mid-sentence should not leave a voice talking.
    unawaited(_announcer.silence());
    super.dispose();
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final discard = await showConfirmDialog(
      context,
      title: 'Discard this walk?',
      message: 'Nothing has been saved yet. The route and the time go with it.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep walking',
      destructive: true,
    );
    if (!discard || !context.mounted) return;
    ref.read(recordingControllerProvider.notifier).discard();
    context.goNamed(Routes.record);
  }

  /// A verse has landed. Chime, buzz, speak, and tell a screen reader.
  ///
  /// Fire-and-forget on purpose: nothing on this screen waits for audio, and
  /// [ScriptureAnnouncer] swallows every platform failure, so a device with no
  /// speech engine simply gets the card.
  void _announce(DeliveredPrompt delivered) {
    final settings = ref.read(recordingControllerProvider).scripture;
    unawaited(
      _announcer
          .announce(
            delivered.prompt,
            sound: settings.sound,
            voice: settings.voice,
            view: View.of(context),
          ),
    );
  }

  void _toggleMute() {
    final controller = ref.read(recordingControllerProvider.notifier);
    final wasMuted = ref.read(recordingControllerProvider).scriptureMuted;
    controller.setScriptureMuted(!wasMuted);
    // Muting has to stop what is being said right now, or the control reads as
    // broken for the eight seconds it takes the verse to finish.
    if (!wasMuted) unawaited(_announcer.silence());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recordingControllerProvider);

    // Each arrival is a fresh object, so identity is what separates "a verse
    // has landed" from "this screen rebuilt".
    ref.listen<DeliveredPrompt?>(
      recordingControllerProvider.select((s) => s.currentPrompt),
      (previous, next) {
        if (next == null || identical(previous, next)) return;
        _announce(next);
      },
    );

    // Pausing is a request for quiet, not only for the clock to stop.
    ref.listen<bool>(
      recordingControllerProvider.select((s) => s.isPaused),
      (_, paused) {
        if (paused) unawaited(_announcer.silence());
      },
    );

    // Steps were asked for and the device could not supply them. Said once,
    // quietly, and never again for this walk.
    ref.listen<bool>(
      recordingControllerProvider.select((s) => s.scriptureFellBackToDistance),
      (_, fellBack) {
        if (!fellBack || _toldAboutFallback || !mounted) return;
        _toldAboutFallback = true;
        showAppSnackBar(
          context,
          'This phone has no step sensor, so verses are paced by distance.',
        );
      },
    );

    if (!state.isLive) {
      // Reached by deep link, or after the recording was finished elsewhere.
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

    final current = state.currentPrompt;

    return PopScope(
      // Leaving mid-walk should be deliberate.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmDiscard(context, ref);
      },
      child: Scaffold(
        backgroundColor: AppColors.pine,
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RouteMapView(
                      points: state.route,
                      waypoints: state.waypoints.toTrailWaypoints(
                        Theme.of(context).trail,
                      ),
                      pulsePoint: state.lastPoint,
                      // The uncertainty, drawn to scale. A dot alone claims a
                      // precision the device has not yet earned.
                      accuracyMeters: state.accuracyMeters,
                      // Keeps the camera on the walker as the route grows.
                      followPoint: state.lastPoint,
                      showEndpoints: false,
                      interactive: false,
                      locatingLabel: state.warmingUp
                          ? 'Getting a sharp signal…'
                          : 'Finding you…',
                      overlay: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: SafeArea(
                            child: SignalIndicator(
                              signal: state.signal,
                              accuracyMeters: state.accuracyMeters,
                              onDark: true,
                            ),
                          ),
                        ),
                      ),
                      semanticLabel:
                          'Map showing the route so far, '
                          '${Fmt.distance(state.distanceMeters)}',
                    ),
                  ),
                  // Outside the map's own overlay slot, which is wrapped in an
                  // IgnorePointer — this one has to be tappable.
                  if (current != null)
                    Positioned(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      bottom: AppSpacing.lg,
                      child: ScriptureArrivalCard(
                        delivered: current,
                        showTranslation: state.scripture.showTranslation,
                        muted: state.scriptureMuted,
                        onToggleMute: _toggleMute,
                        onDismiss: () => ref
                            .read(recordingControllerProvider.notifier)
                            .dismissPrompt(),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: _LivePanel(
                state: state,
                onTogglePause: () =>
                    ref.read(recordingControllerProvider.notifier).togglePause(),
                onDropWaypoint: () => _openWaypointSheet(context, ref),
                onToggleMute: _toggleMute,
                onFinish: () {
                  unawaited(_announcer.silence());
                  ref.read(recordingControllerProvider.notifier).finish();
                  context.goNamed(Routes.activitySummary);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWaypointSheet(BuildContext context, WidgetRef ref) async {
    final kind = await showModalBottomSheet<WaypointKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Mark this spot',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final option in WaypointKind.values)
                ListTile(
                  leading: Icon(
                    Icons.local_fire_department_rounded,
                    color: theme.colorScheme.tertiary,
                  ),
                  title: Text(option.label),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
    if (kind == null || !context.mounted) return;
    ref.read(recordingControllerProvider.notifier).dropWaypoint(kind);
    showAppSnackBar(context, '${kind.label} — marked on your trail.');
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.state,
    required this.onTogglePause,
    required this.onDropWaypoint,
    required this.onToggleMute,
    required this.onFinish,
  });

  final RecordingState state;
  final VoidCallback onTogglePause;
  final VoidCallback onDropWaypoint;
  final VoidCallback onToggleMute;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onDark = AppColors.parchment;
    final muted = onDark.withValues(alpha: 0.72);
    final type = state.type;
    final isPaused = state.isPaused;

    final paceValue = type.usesSpeed
        ? Fmt.speed(state.distanceMeters, state.elapsed)
        : Fmt.pace(state.distanceMeters, state.elapsed);
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
              // Recording on approximate permission. This stays on screen for
              // the whole walk on purpose: the resulting trace can be a
              // kilometre out, and the walker should never have to work that
              // out for themselves afterwards.
              if (state.isApproximate)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.blur_on_rounded,
                        size: 16,
                        color: AppColors.amber,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'Approximate location only — this trace will be rough.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (isPaused)
                _LiveBadge(label: 'PAUSED', theme: theme)
              // The warm-up gate is deliberately visible: the walk has started
              // and nothing is being plotted yet, which without a word on
              // screen looks like the app has frozen.
              else if (state.warmingUp)
                _LiveBadge(label: 'GETTING A SHARP SIGNAL…', theme: theme)
              else if (state.route.isEmpty)
                _LiveBadge(label: 'FINDING YOU…', theme: theme),
              // A three-figure distance at a large text setting is wider than
              // the panel. It scales rather than spilling; nothing else on this
              // screen moves.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.distanceValue(state.distanceMeters),
                  maxLines: 1,
                  style: AppTypography.statDisplay(onDark, size: 64),
                ),
              ),
              Text(
                '${Fmt.distanceUnit(state.distanceMeters)}  ·  ${type.label.toLowerCase()}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Loose flex: each readout keeps its natural width and the
                  // spacing stays even, but none of the three can push the row
                  // wider than the panel — an hour-long walk's `1:23:45` and a
                  // large text setting both land here.
                  Flexible(
                    child: _LiveStat(
                      label: 'Time',
                      value: Fmt.duration(state.elapsed),
                      onDark: onDark,
                      muted: muted,
                    ),
                  ),
                  Flexible(
                    child: _LiveStat(
                      label: paceLabel,
                      value: paceValue,
                      onDark: onDark,
                      muted: muted,
                    ),
                  ),
                  Flexible(
                    child: _LiveStat(
                      label: 'Elevation',
                      value: state.elevationGainMeters.round().toString(),
                      unit: 'm',
                      onDark: onDark,
                      muted: muted,
                    ),
                  ),
                ],
              ),
              if (state.intentions.isNotEmpty) ...[
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
                        state.intentions.first.text,
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              if (state.scripture.enabled) ...[
                const SizedBox(height: AppSpacing.lg),
                _ScriptureStrip(
                  state: state,
                  onDark: onDark,
                  muted: muted,
                  onToggleMute: onToggleMute,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                // Needs a position to pin the marker to.
                onPressed: state.lastPoint == null ? null : onDropWaypoint,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(
                  state.waypoints.isEmpty
                      ? 'Mark a prayer'
                      : '${Fmt.plural(state.waypoints.length, 'mark')} on this walk',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.amber,
                  side: BorderSide(color: AppColors.amber.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Keep the app open — recording stops if you lock the screen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything scripture has said on this walk, and the way to make it stop.
///
/// The list is the safety net for the whole feature: a card that auto-dismisses
/// is only kind if what it showed is still somewhere. A verse that arrived
/// while the phone was in a pocket is here, in order, until the walk ends.
class _ScriptureStrip extends StatelessWidget {
  const _ScriptureStrip({
    required this.state,
    required this.onDark,
    required this.muted,
    required this.onToggleMute,
  });

  final RecordingState state;
  final Color onDark;
  final Color muted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delivered = state.deliveredPrompts;
    final isMuted = state.scriptureMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 16,
              color: onDark.withValues(alpha: 0.8),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                delivered.isEmpty
                    ? 'Scripture on the trail'
                    : Fmt.plural(delivered.length, 'verse'),
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // The one-tap mute, in a fixed place for the whole walk.
            IconButton(
              onPressed: onToggleMute,
              iconSize: 20,
              color: isMuted ? muted : AppColors.amber,
              tooltip: isMuted ? 'Unmute scripture' : 'Mute scripture',
              icon: Icon(
                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              ),
            ),
          ],
        ),
        if (delivered.isEmpty)
          Text(
            'The first one arrives once you are on your way.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          )
        else
          for (final item in delivered.reversed)
            _DeliveredRow(
              delivered: item,
              onDark: onDark,
              muted: muted,
              showTranslation: state.scripture.showTranslation,
            ),
      ],
    );
  }
}

class _DeliveredRow extends StatelessWidget {
  const _DeliveredRow({
    required this.delivered,
    required this.onDark,
    required this.muted,
    required this.showTranslation,
  });

  final DeliveredPrompt delivered;
  final Color onDark;
  final Color muted;
  final bool showTranslation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = delivered.prompt;

    return InkWell(
      onTap: () => showScriptureReading(
        context,
        prompt,
        showTranslation: showTranslation,
      ),
      borderRadius: AppRadius.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: AppSpacing.md),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).trail.waypointScripture,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prompt.reference,
                    style: theme.textTheme.bodyMedium?.copyWith(color: onDark),
                  ),
                  Text(
                    prompt.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              Fmt.durationShort(delivered.elapsed),
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one-word status above the distance: paused, warming up, or still
/// looking. Only ever one of them at a time.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.amber,
          letterSpacing: 2,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Figure and unit stay one reading on one baseline, scaling together
          // when the slot is too narrow rather than breaking apart.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: AppTypography.statValue(onDark, size: 26),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
