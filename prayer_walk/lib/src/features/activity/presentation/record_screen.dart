import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/mock_activity_repository.dart';
import '../data/recording_controller.dart';
import '../domain/activity.dart';
import 'widgets/intentions_sheet.dart';

/// Pre-activity: pick what you are doing, name what you are carrying, start.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  bool _starting = false;

  Future<void> _openIntentions() async {
    final current = ref.read(recordingControllerProvider).intentions;
    final chosen = await showIntentionsSheet(context, initial: current);
    if (chosen == null) return;
    ref.read(recordingControllerProvider.notifier).setDraftIntentions(chosen);
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await ref.read(recordingControllerProvider.notifier).start();
      if (mounted) context.goNamed(Routes.liveTracking);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          "Couldn't start the recording. Try again in a moment.",
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(recordingControllerProvider);
    final location = ref.watch(currentLocationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: Column(
        children: [
          Expanded(
            child: AsyncView<LatLng>(
              value: location,
              onRetry: () => ref.invalidate(currentLocationProvider),
              loading: const ShimmerScope(child: SkeletonBox(height: 400, radius: 0)),
              data: (center) => RouteMapView(
                center: center,
                pulsePoint: center,
                initialZoom: 16,
                semanticLabel: 'Map of your current area',
              ),
            ),
          ),
          _RecordPanel(
            state: state,
            starting: _starting,
            onSelectType: (type) => ref
                .read(recordingControllerProvider.notifier)
                .selectType(type),
            onEditIntentions: _openIntentions,
            onDropDevotional: () =>
                ref.read(recordingControllerProvider.notifier).dropDevotional(),
            onStart: _start,
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
    required this.starting,
    required this.onSelectType,
    required this.onEditIntentions,
    required this.onDropDevotional,
    required this.onStart,
  });

  final RecordingState state;
  final bool starting;
  final ValueChanged<ActivityType> onSelectType;
  final VoidCallback onEditIntentions;
  final VoidCallback onDropDevotional;
  final VoidCallback onStart;

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
              const SizedBox(height: AppSpacing.lg),

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
                'Preview build — the recording is simulated. Real tracking '
                'arrives in the next phase.',
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
