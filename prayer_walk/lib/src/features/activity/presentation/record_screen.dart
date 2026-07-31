import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/presentation/scripture_settings_panel.dart';
import '../data/location_service.dart';
import '../data/activity_providers.dart';
import '../data/recording_controller.dart';
import '../data/recording_journal.dart';
import '../domain/activity.dart';
import '../domain/interrupted_recording.dart';
import 'widgets/intentions_sheet.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-RECORD';

/// Pre-activity: pick what you are doing, name what you are carrying, start.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    // Warms the verse library while the walker is still choosing what they are
    // carrying, so pressing Start never waits on a request. Reading the
    // provider is what starts it; the result is held for the walk.
    ref.read(scriptureLibraryProvider);
  }

  Future<void> _openIntentions() async {
    final current = ref.read(recordingControllerProvider).intentions;
    final chosen = await showIntentionsSheet(context, initial: current);
    if (chosen == null) return;
    ref.read(recordingControllerProvider.notifier).setDraftIntentions(chosen);
  }

  Future<void> _start() async {
    // Starting a fresh walk overwrites the journal, so an unresolved one has to
    // be resolved first — the card above the button is the offer, and this is
    // what stops the offer from being answered by accident.
    if (!await _clearedToStart()) return;
    if (!mounted) return;
    setState(() => _starting = true);
    // Fired on the press, not on the result: the walk begins when the thumb
    // lifts, and a permission prompt can sit in between.
    AppHaptics.heavy();
    try {
      // Runs the OS permission gate. A denial is an ordinary answer, not an
      // error — it comes back as a [LocationAccess] the panel explains.
      final access = await ref
          .read(recordingControllerProvider.notifier)
          .start();
      if (!mounted) return;
      // Approximate counts as started: the walk records, and the live screen
      // carries the warning that the trace will be rough.
      if (access.canRecord) {
        context.goNamed(Routes.liveTracking);
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The recording didn't start.",
          onRetry: _start,
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  // ------------------------------------------------ the walk that was lost ---

  /// Whether a new walk may begin, given whatever unfinished one is waiting.
  ///
  /// Answers true immediately in the ordinary case, where nothing is waiting.
  /// When something is, the walker is told what pressing Start costs and given
  /// the door they probably wanted — "Save it first" leaves the old walk on the
  /// summary screen and the new one unstarted, which is recoverable in a way
  /// that overwriting it is not.
  Future<bool> _clearedToStart() async {
    final current = ref.read(recordingControllerProvider);
    // Same suppression the card uses: the journal describes a live walk and an
    // unsaved draft as well as a lost one, and neither of those is something to
    // warn about here.
    if (current.isLive || current.hasDraft) return true;
    final waiting = ref.read(interruptedRecordingProvider).value;
    if (waiting == null) return true;

    final saveFirst = await showConfirmDialog(
      context,
      title: 'Save your unfinished walk first?',
      message:
          '${Fmt.distance(waiting.distanceMeters)} of an earlier walk has not '
          'been saved yet. Starting a new one now replaces it.',
      confirmLabel: 'Save it first',
      cancelLabel: 'Start a new walk',
    );
    if (!saveFirst) return true;
    if (!mounted) return false;
    _keepInterrupted(waiting);
    return false;
  }

  /// Picks the interrupted walk back up and goes straight to the live screen.
  Future<void> _resumeInterrupted(InterruptedRecording walk) async {
    setState(() => _starting = true);
    AppHaptics.heavy();
    try {
      final access = await ref
          .read(recordingControllerProvider.notifier)
          .resumeInterrupted(walk);
      if (!mounted) return;
      if (access.canRecord) context.goNamed(Routes.liveTracking);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That walk couldn't be picked up again.",
          onRetry: () => _resumeInterrupted(walk),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Takes the interrupted walk as finished and goes to the summary, where it
  /// is titled and saved like any other.
  void _keepInterrupted(InterruptedRecording walk) {
    AppHaptics.heavy();
    ref.read(recordingControllerProvider.notifier).keepInterrupted(walk);
    context.goNamed(Routes.activitySummary);
  }

  /// The only path that throws a recovered walk away, and it asks first.
  Future<void> _discardInterrupted(InterruptedRecording walk) async {
    final discard = await showConfirmDialog(
      context,
      title: 'Throw this walk away?',
      message:
          '${Fmt.distance(walk.distanceMeters)} and '
          '${Fmt.duration(walk.elapsed)} were recorded before the app stopped. '
          'Nothing about them is kept.',
      confirmLabel: 'Throw away',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!discard) return;
    await ref.read(recordingControllerProvider.notifier).discardInterrupted();
  }

  /// Why a walk gets interrupted, and the one setting that usually fixes it.
  ///
  /// Only ever reached by somebody tapping "Why did this happen?" on a walk
  /// that actually was interrupted — so it is never a prompt, never a banner,
  /// and never shown to the great majority of walkers whose phones behave. That
  /// is deliberate: this is a manufacturer's battery manager, not something the
  /// app can detect reliably or fix on the walker's behalf, and a permanent
  /// nag about it would cost more than it saves.
  Future<void> _explainInterruption() async {
    final open = await showConfirmDialog(
      context,
      title: 'Why a walk stops',
      message:
          'Prayer Walk keeps recording in the background, but some phones — '
          'Xiaomi, Huawei, Samsung, Oppo and OnePlus especially — close apps '
          'that run for a long time with the screen off, whatever the app asks '
          'for.\n\nIf this keeps happening, find Prayer Walk in your phone\'s '
          'Settings, open Battery, and set it to Unrestricted (some phones call '
          'it "Don\'t optimise" or "Allow background activity").',
      confirmLabel: 'Open settings',
      cancelLabel: 'Not now',
    );
    if (!open) return;
    await ref.read(locationServiceProvider).openAppSettings();
  }

  /// The action that actually fixes each blocked case.
  Future<void> _resolveAccess(LocationAccess access) async {
    final service = ref.read(locationServiceProvider);
    switch (access) {
      case LocationAccess.serviceDisabled:
        await service.openLocationSettings();
      case LocationAccess.deniedForever:
        await service.openAppSettings();
      case LocationAccess.grantedApproximate:
        // Precise location can only be turned on by the person, in system
        // settings. On iOS the temporary-accuracy prompt has already been shown
        // and declined by the time we get here, so app settings is the only
        // route left on either platform.
        await service.openAppSettings();
        // Coming back from settings, re-read: the answer may have changed.
        ref.invalidate(currentLocationProvider);
      case LocationAccess.denied:
        // Still askable — go straight back through the prompt.
        await _start();
      case LocationAccess.granted:
        break;
    }
  }

  /// Why the map has nothing to centre on. Each of these is a different
  /// problem with a different fix, and none of them is "you are in Manila".
  static String _locatingLabel(LocationAccess access) => switch (access) {
    LocationAccess.serviceDisabled => 'Location is switched off',
    LocationAccess.denied ||
    LocationAccess.deniedForever => 'Location is not shared',
    LocationAccess.granted ||
    LocationAccess.grantedApproximate => 'Finding you…',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(recordingControllerProvider);
    final location = ref.watch(currentLocationProvider);

    // What the panel should complain about: whatever the last start attempt
    // reported, or — before any attempt — whatever the device just told us.
    // `granted` is the silent case; everything else has something to say.
    final access =
        state.access ?? location.value?.access ?? LocationAccess.granted;

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<LocationReading>(
              value: location,
              errorFallback: "Your location couldn't be found.",
              onRetry: () => ref.invalidate(currentLocationProvider),
              loading: const RouteMapView(locatingLabel: 'Finding you…'),
              data: (reading) {
                final fix = reading.fix;
                if (fix == null) {
                  // No trustworthy position. Say which kind of "no" this is
                  // rather than centring the map on a guess.
                  return RouteMapView(
                    locatingLabel: _locatingLabel(reading.access),
                  );
                }
                return RouteMapView(
                  center: fix.point,
                  pulsePoint: fix.point,
                  accuracyMeters: fix.accuracyMeters,
                  initialZoom: 16,
                  semanticLabel: 'Map of your current area',
                  overlay: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SignalIndicator(
                        signal: fix.signal,
                        accuracyMeters: fix.accuracyMeters,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _RecordPanel(
            state: state,
            access: access,
            // Null on every ordinary launch. Present only when the app was
            // killed mid-walk, and then it is the first thing on the panel —
            // above the type chips, above Start — because starting a second
            // walk on top of an unresolved one is how the first gets lost.
            //
            // Suppressed outright while a walk is live or a draft is waiting on
            // the summary screen. The journal describes both of those too, and
            // offering the walk somebody is *currently on* back to them as
            // "unfinished" would be nonsense.
            interrupted: state.isLive || state.hasDraft
                ? null
                : ref.watch(interruptedRecordingProvider).value,
            onResumeInterrupted: _resumeInterrupted,
            onKeepInterrupted: _keepInterrupted,
            onDiscardInterrupted: _discardInterrupted,
            onExplainInterruption: _explainInterruption,
            starting: _starting,
            onSelectType: (type) {
              AppHaptics.selection();
              ref.read(recordingControllerProvider.notifier).selectType(type);
            },
            onEditIntentions: _openIntentions,
            onDropDevotional: () =>
                ref.read(recordingControllerProvider.notifier).dropDevotional(),
            onStart: _start,
            onResolveAccess: _resolveAccess,
          ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _RecordPanel extends StatelessWidget {
  const _RecordPanel({
    required this.state,
    required this.access,
    required this.interrupted,
    required this.onResumeInterrupted,
    required this.onKeepInterrupted,
    required this.onDiscardInterrupted,
    required this.onExplainInterruption,
    required this.starting,
    required this.onSelectType,
    required this.onEditIntentions,
    required this.onDropDevotional,
    required this.onStart,
    required this.onResolveAccess,
  });

  final RecordingState state;

  /// The current access level. [LocationAccess.granted] shows no notice;
  /// everything else, including an approximate grant, has something the walker
  /// needs to know before they set off.
  final LocationAccess access;

  /// A walk the app was recording when it stopped running, or null — which is
  /// what this is on essentially every launch.
  final InterruptedRecording? interrupted;

  final ValueChanged<InterruptedRecording> onResumeInterrupted;
  final ValueChanged<InterruptedRecording> onKeepInterrupted;
  final ValueChanged<InterruptedRecording> onDiscardInterrupted;
  final VoidCallback onExplainInterruption;

  final bool starting;
  final ValueChanged<ActivityType> onSelectType;
  final VoidCallback onEditIntentions;
  final VoidCallback onDropDevotional;
  final VoidCallback onStart;
  final ValueChanged<LocationAccess> onResolveAccess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.sheet,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (interrupted != null) ...[
                _InterruptedWalkCard(
                  walk: interrupted!,
                  onResume: () => onResumeInterrupted(interrupted!),
                  onKeep: () => onKeepInterrupted(interrupted!),
                  onDiscard: () => onDiscardInterrupted(interrupted!),
                  onExplain: onExplainInterruption,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final type in ActivityType.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ActivityTypeFilterChip(
                          label: type.label,
                          icon: ActivityTypeVisuals.icon(type),
                          selected: state.type == type,
                          onSelected: () => onSelectType(type),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              if (state.devotionalTitle != null) ...[
                _CarryingDevotional(
                  title: state.devotionalTitle!,
                  onRemove: onDropDevotional,
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              InkWell(
                onTap: onEditIntentions,
                borderRadius: AppRadius.control,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.minTapTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.control,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_outlined,
                        size: 20,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          state.intentions.isEmpty
                              ? 'Add intentions'
                              : state.intentions.map((i) => i.text).join(' · '),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.intentions.isNotEmpty)
                        Text(
                          Fmt.plural(state.intentions.length, 'intention'),
                          style: theme.textTheme.labelSmall,
                        ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              const _ScriptureTile(),
              const SizedBox(height: AppSpacing.lg),

              if (access != LocationAccess.granted) ...[
                _AccessNotice(
                  access: access,
                  onResolve: () => onResolveAccess(access),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              PrimaryButton(
                label: 'Start ${state.type.label.toLowerCase()}',
                icon: ActivityTypeVisuals.icon(state.type),
                expand: true,
                large: true,
                busy: starting,
                onPressed: onStart,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Said before the walk, not during it, because it is the thing
              // that decides whether somebody puts the phone away and prays or
              // holds it up and watches it. The notification is named because
              // one appearing unannounced reads as something having gone wrong.
              Text(
                'Your route keeps recording with the screen locked or the phone '
                'in a pocket. A notification shows while a walk is running, and '
                'your location is read only between Start and Finish.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A walk the app was recording when it stopped running, offered back.
///
/// The whole point is that it is *offered*, never assumed. An interrupted walk
/// is not resumed by itself — silently restarting the GPS and the notification
/// for somebody who finished walking an hour ago and opened the app to read the
/// feed would be its own kind of failure — and it is never thrown away by
/// itself either. Three doors, all of them explicit:
///
///  * **Pick it up** carries on recording from where it stopped. Hidden once
///    the gap is long enough that resuming would mean stitching two different
///    walks together; the walk is still offered, just not as a live one.
///  * **Save it** treats it as finished and goes to the ordinary summary
///    screen, so a recovered walk is titled, made public or private, and stored
///    exactly like every other walk.
///  * **Throw it away** asks first, and is deliberately the quietest of the
///    three.
class _InterruptedWalkCard extends StatelessWidget {
  const _InterruptedWalkCard({
    required this.walk,
    required this.onResume,
    required this.onKeep,
    required this.onDiscard,
    required this.onExplain,
  });

  final InterruptedRecording walk;
  final VoidCallback onResume;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canResume = !walk.isTooOldToResume;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: AppRadius.control,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.restore_rounded,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'You have an unfinished walk',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Everything the walker needs to recognise it: how much of it there
            // is, and how long ago it stopped. The gap is what tells them
            // whether picking it up makes sense.
            '${Fmt.distance(walk.distanceMeters)} · '
            '${Fmt.duration(walk.elapsed)} · '
            'stopped ${Fmt.relativeTime(walk.lastSeenAt).toLowerCase()}. '
            '${canResume ? 'Carry on with it, or save it as it is.' : 'Too long ago to carry on with — save it as it is.'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (canResume) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSizes.minTapTarget),
                    ),
                    child: const Text('Pick it up'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: canResume
                    ? OutlinedButton(
                        onPressed: onKeep,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSizes.minTapTarget),
                          foregroundColor: scheme.onTertiaryContainer,
                        ),
                        child: const Text('Save it'),
                      )
                    : FilledButton(
                        onPressed: onKeep,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, AppSizes.minTapTarget),
                        ),
                        child: const Text('Save it'),
                      ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppTextButton(label: 'Why did this happen?', onPressed: onExplain),
              AppTextButton(label: 'Throw it away', onPressed: onDiscard),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pre-walk scripture control: on or off, how often, and from where.
///
/// Deliberately the same weight and shape as the intentions row above it —
/// something you set on the way out of the door, not a feature being sold.
/// Whatever is chosen here is remembered, so it does not have to be set again
/// before every walk.
class _ScriptureTile extends ConsumerWidget {
  const _ScriptureTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(scriptureSettingsProvider);
    final on = settings.enabled;

    return InkWell(
      onTap: () => showScriptureSettingsSheet(context),
      borderRadius: AppRadius.control,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.control,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.menu_book_rounded : Icons.menu_book_outlined,
              size: 20,
              color: on
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Scripture on the trail',
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                scriptureSummary(settings),
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// What is wrong with the app's location access, and the one thing that fixes
/// it.
///
/// Each case gets its own action because they are genuinely different problems:
/// a fresh denial can just be asked again, a permanent one needs app settings,
/// location being switched off isn't a permission matter at all, and an
/// *approximate* grant is not a failure — recording works, it just will not be
/// accurate, and the walker is owed that fact before they set off rather than
/// after they look at a route that misses their street by a kilometre.
class _AccessNotice extends StatelessWidget {
  const _AccessNotice({required this.access, required this.onResolve});

  final LocationAccess access;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Approximate is a warning, not an error: nothing is blocked, so it does
    // not get the error colour or the alarm.
    final blocking = !access.canRecord;

    final (message, action, icon) = switch (access) {
      LocationAccess.serviceDisabled => (
        'Location is switched off on this device, so there is no route to '
            'record.',
        'Turn on location',
        Icons.location_off_outlined,
      ),
      LocationAccess.deniedForever => (
        'Prayer Walk cannot see your location. Allow it in Settings to record '
            'a route.',
        'Open settings',
        Icons.location_off_outlined,
      ),
      LocationAccess.denied => (
        'Prayer Walk needs your location to trace the route you walk.',
        'Allow location',
        Icons.location_off_outlined,
      ),
      LocationAccess.grantedApproximate => (
        'Only approximate location is shared, which is accurate to about a '
            'kilometre. You can still walk, but the trace will be rough. Turn '
            'on Precise location to record the route properly.',
        'Open settings',
        Icons.blur_on_rounded,
      ),
      LocationAccess.granted => ('', '', Icons.check_rounded),
    };

    final background = blocking
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = blocking
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.control,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton(label: action, onPressed: onResolve),
          ),
        ],
      ),
    );
  }
}

class _CarryingDevotional extends StatelessWidget {
  const _CarryingDevotional({required this.title, required this.onRemove});

  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Walking with "$title"',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            iconSize: 18,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Walk without this devotional',
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ],
      ),
    );
  }
}
