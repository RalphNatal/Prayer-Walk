import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../activity/data/activity_providers.dart';
import '../data/privacy_actions.dart';
import '../data/privacy_providers.dart';
import '../domain/privacy_zone.dart';
import 'zone_editor_screen.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ZONES';

/// Places a walk must not be shown starting from.
///
/// The most consequential screen in this feature and the plainest — a list, a
/// paragraph that says what a zone actually does, and one button. Nothing here
/// is phrased as a warning: setting a zone is an ordinary thing a person does
/// once, and a screen that alarms them about their own home is a screen they
/// will close.
class PrivacyZonesScreen extends ConsumerWidget {
  const PrivacyZonesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    PrivacyZone? existing,
  }) async {
    // The device's own position, if it has one, so a new zone opens on the
    // street the person is standing in rather than on an arbitrary continent.
    // Null is ordinary — the editor says so and waits.
    final reading = await ref.read(currentLocationProvider.future).then<
      LatLng?
    >((r) => r.fix?.point, onError: (_, _) => null);

    if (!context.mounted) return;

    final draft = await Navigator.of(context).push<PrivacyZoneDraft>(
      MaterialPageRoute(
        builder: (_) => ZoneEditorScreen(
          initial: existing == null
              ? null
              : PrivacyZoneDraft.from(existing),
          fallbackCentre: reading,
        ),
      ),
    );
    if (draft == null || !context.mounted) return;

    try {
      await ref.read(privacyActionsProvider).saveZone(draft);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That zone didn't save.",
        );
      }
      return;
    }
    if (context.mounted) {
      showAppSnackBar(
        context,
        existing == null
            ? '"${draft.label}" added. Walks are trimmed here from now on.'
            : '"${draft.label}" updated.',
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PrivacyZone zone,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove "${zone.label}"?',
      message:
          'Walks that pass through here stop being trimmed — the full route, '
          'both ends included, becomes part of anything you have shared.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      await ref.read(privacyActionsProvider).deleteZone(zone.id);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That zone wasn't removed.",
        );
      }
      return;
    }
    if (context.mounted) {
      showAppSnackBar(context, '"${zone.label}" removed.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(privacyZonesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy zones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add a zone'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(privacyZonesProvider.future),
        child: AsyncView<List<PrivacyZone>>(
          value: zones,
          errorFallback: "Your zones couldn't be loaded.",
          onRetry: () => ref.invalidate(privacyZonesProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 2),
          ),
          empty: () => ScrollableStateBody(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  child: _ZoneExplainer(),
                ),
                EmptyState(
                  icon: Icons.home_outlined,
                  title: 'No zones yet',
                  message:
                      'Most walks start and finish at home. A zone there is '
                      'the one setting worth having before you share anything.',
                  actionLabel: 'Add a zone',
                  onAction: () => _edit(context, ref),
                ),
              ],
            ),
          ),
          data: (items) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.listBody,
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              if (index == 0) return const _ZoneExplainer();
              final zone = items[index - 1];
              return _ZoneRow(
                zone: zone,
                onEdit: () => _edit(context, ref, existing: zone),
                onDelete: () => _delete(context, ref, zone),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What a zone does, said once, in full, at the top.
class _ZoneExplainer extends StatelessWidget {
  const _ZoneExplainer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              PrivacyZone.explainer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.onEdit,
    required this.onDelete,
  });

  final PrivacyZone zone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.control,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.adjust_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zone.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      // Radius and nothing else. The coordinates are not
                      // rendered anywhere in this app, on any screen, for
                      // anybody — including their owner on a shared screen in
                      // a coffee shop.
                      '${Fmt.distance(zone.radiusMeters.toDouble())} around a '
                      'saved point',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
