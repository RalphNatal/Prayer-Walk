import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/activity_providers.dart';
import '../data/recording_controller.dart';
import '../domain/activity.dart';
import 'trail_mapping.dart';
import 'widgets/intentions_sheet.dart';

/// Log tag for this screen's failures. `[PW-SUMMARY]` is what to grep for when
/// a walk refuses to save.
const _tag = 'PW-SUMMARY';

/// What you just walked, before it is saved.
class ActivitySummaryScreen extends ConsumerStatefulWidget {
  const ActivitySummaryScreen({super.key});

  @override
  ConsumerState<ActivitySummaryScreen> createState() =>
      _ActivitySummaryScreenState();
}

class _ActivitySummaryScreenState extends ConsumerState<ActivitySummaryScreen> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  bool _seeded = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _editIntentions() async {
    final current = ref.read(recordingControllerProvider).intentions;
    final chosen = await showIntentionsSheet(context, initial: current);
    if (chosen == null) return;
    ref.read(recordingControllerProvider.notifier).setDraftIntentions(chosen);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = ref.read(recordingControllerProvider.notifier);
    controller.editDraft(title: _title.text, note: _note.text);
    try {
      final id = await controller.save();
      // History and the profile's recent-walks strip both read the real rows.
      // The feed is still mock and unaffected by a real save.
      ref
        ..invalidate(historyProvider)
        ..invalidate(activitiesForUserProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Walk saved.');
      context.goNamed(
        Routes.activityDetail,
        pathParameters: {'activityId': id},
      );
    } catch (error, stack) {
      // The draft is untouched: [RecordingController.save] only clears the
      // recording after the write comes back. An hour on the road survives a
      // failed save, and Retry sends the same walk again.
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The walk didn't save. It's still here — try again.",
          onRetry: _save,
          retryLabel: 'Retry',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Discard this walk?',
      message: 'The route, the time and the intentions go with it.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    ref.read(recordingControllerProvider.notifier).discard();
    if (mounted) context.goNamed(Routes.record);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(recordingControllerProvider);
    final draft = state.draft;

    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Summary')),
        body: Center(
          child: EmptyState(
            icon: Icons.route_outlined,
            title: 'Nothing to save',
            message: 'This walk has already been saved or discarded.',
            actionLabel: 'Go to history',
            onAction: () => context.goNamed(Routes.history),
          ),
        ),
      );
    }

    if (!_seeded) {
      _seeded = true;
      _title.text = draft.title;
      _note.text = draft.note;
    }

    final paceLabel = draft.type.usesSpeed
        ? Fmt.speed(draft.distanceMeters, draft.duration)
        : Fmt.pace(draft.distanceMeters, draft.duration);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finished'),
        automaticallyImplyLeading: false,
        actions: [
          AppTextButton(label: 'Discard', onPressed: _discard, destructive: true),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          RouteMapView(
            points: draft.route,
            waypoints: draft.waypoints.toTrailWaypoints(),
            height: 260,
            interactive: false,
            semanticLabel:
                'Map of the walk you just finished, '
                '${Fmt.distance(draft.distanceMeters)}',
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Well walked.',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Fmt.dayAndTime(draft.startedAt),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),

                StatStrip(
                  children: [
                    StatTile(
                      label: 'Distance',
                      value: Fmt.distanceValue(draft.distanceMeters),
                      unit: Fmt.distanceUnit(draft.distanceMeters),
                    ),
                    StatTile(
                      label: 'Time',
                      value: Fmt.duration(draft.duration),
                    ),
                    StatTile(
                      label: draft.type.usesSpeed ? 'Speed' : 'Pace',
                      value: paceLabel,
                      unit: draft.type.usesSpeed ? 'km/h' : '/km',
                    ),
                    StatTile(
                      label: 'Climb',
                      value: draft.elevationGainMeters.round().toString(),
                      unit: 'm',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name this walk',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _IntentionsEditor(
                  intentions: state.intentions,
                  onEdit: _editIntentions,
                ),
                const SizedBox(height: AppSpacing.lg),

                TextField(
                  controller: _note,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'What happened out there?',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (draft.waypoints.isNotEmpty) ...[
                  const SectionHeader(title: 'Prayer waypoints'),
                  for (final waypoint in draft.waypoints)
                    _WaypointRow(waypoint: waypoint),
                  const SizedBox(height: AppSpacing.xl),
                ],

                PrimaryButton(
                  label: 'Save walk',
                  expand: true,
                  large: true,
                  busy: _saving,
                  onPressed: _save,
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: AppTextButton(
                    label: 'Discard instead',
                    onPressed: _discard,
                    destructive: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntentionsEditor extends StatelessWidget {
  const _IntentionsEditor({required this.intentions, required this.onEdit});

  final List<PrayerIntention> intentions;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Intentions', style: theme.textTheme.titleSmall),
              ),
              AppTextButton(
                label: intentions.isEmpty ? 'Add' : 'Edit',
                icon: intentions.isEmpty ? Icons.add_rounded : Icons.edit_outlined,
                onPressed: onEdit,
              ),
            ],
          ),
          if (intentions.isEmpty)
            Text(
              'Nothing named yet. Add what you carried.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final intention in intentions)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        size: 15,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        intention.text,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _WaypointRow extends StatelessWidget {
  const _WaypointRow({required this.waypoint});

  final Waypoint waypoint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6, right: AppSpacing.md),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.tertiary,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(waypoint.label, style: theme.textTheme.bodyLarge),
                Text(
                  '${waypoint.kind.label}  ·  ${Fmt.durationShort(waypoint.elapsed)} in',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
