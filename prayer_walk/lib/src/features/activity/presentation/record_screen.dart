import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/presentation/scripture_settings_panel.dart';
import '../data/location_service.dart';
import '../data/activity_providers.dart';
import '../data/recording_controller.dart';
import '../domain/activity.dart';
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
    setState(() => _starting = true);
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
            starting: _starting,
            onSelectType: (type) => ref
                .read(recordingControllerProvider.notifier)
                .selectType(type),
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
              Text(
                'Your route is recorded while the app is open. Locked-screen '
                'tracking comes later.',
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
