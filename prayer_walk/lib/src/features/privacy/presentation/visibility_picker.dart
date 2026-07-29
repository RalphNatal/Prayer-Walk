import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/privacy_actions.dart';
import '../data/privacy_providers.dart';
import '../domain/activity_visibility.dart';
import '../domain/privacy_zone.dart';

/// The icon each setting wears, everywhere it appears.
///
/// Kept here rather than on the enum so the domain stays free of Flutter. Three
/// icons that read as a widening circle: a lock, a pair of people, a globe.
IconData visibilityIcon(ActivityVisibility visibility) => switch (visibility) {
  ActivityVisibility.private => Icons.lock_outline_rounded,
  ActivityVisibility.followers => Icons.people_outline_rounded,
  ActivityVisibility.public => Icons.public_rounded,
};

/// Choosing who a walk is for.
///
/// Three rows rather than a segmented control, because each option needs its
/// sentence next to it. This is the one setting in the app where not reading
/// the label has a consequence that happens outdoors, to a real address, and a
/// three-word segment cannot carry "any member can find this walk, including
/// people you have never met".
///
/// Choosing [ActivityVisibility.public] for the first time opens
/// [showPublicWalkNotice] before the change is accepted. Declining there leaves
/// the previous setting in place — the dialog is a step in the choice, not an
/// acknowledgement after it.
class VisibilityPicker extends ConsumerWidget {
  const VisibilityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final ActivityVisibility value;
  final ValueChanged<ActivityVisibility> onChanged;

  /// Drops the per-option descriptions, for the places where the setting is
  /// being changed rather than chosen for the first time.
  final bool dense;

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ActivityVisibility chosen,
  ) async {
    if (chosen == value) return;

    if (chosen.reachesStrangers) {
      final seen = await ref.read(publicWalkNoticeSeenProvider.future);
      if (!seen) {
        if (!context.mounted) return;
        final accepted = await showPublicWalkNotice(context, ref);
        if (!accepted) return;
      }
    }
    onChanged(chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // The group owns the selection and the callback; the tiles only declare
    // their value. Choosing `public` is intercepted in [_select] rather than
    // applied here, so the one-time explanation is a step inside the choice
    // instead of an acknowledgement after it.
    return RadioGroup<ActivityVisibility>(
      groupValue: value,
      onChanged: (chosen) {
        if (chosen != null) _select(context, ref, chosen);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in ActivityVisibility.values)
            RadioListTile<ActivityVisibility>(
              value: option,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Row(
                children: [
                  Icon(
                    visibilityIcon(option),
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      option.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              subtitle: dense
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 26),
                      child: Text(
                        option.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// B4 · The one-time explanation, shown the first time somebody chooses to make
/// a walk public.
///
/// Non-alarmist on purpose. It is not a warning that something bad is about to
/// happen — a public walk is a perfectly good thing to want — it is the one
/// fact that is genuinely not obvious from the word "Everyone": that a route is
/// a trace of where the walker's feet were, and that where they started is
/// usually where they live.
///
/// It offers the fix in the same breath rather than leaving somebody to find
/// Settings on their own, and it is dismissed by a real choice. "Not yet" is a
/// valid answer that leaves the walk exactly as private as it was.
///
/// Returns whether the member accepted. The flag is only marked seen on
/// acceptance, so somebody who backed out is asked again next time — this is a
/// consequence worth explaining twice rather than a modal to be trained past.
Future<bool> showPublicWalkNotice(BuildContext context, WidgetRef ref) async {
  final zones = await ref.read(privacyZonesProvider.future).catchError(
    // The dialog matters more than the count in it. A failed read of the zone
    // list should not stop somebody being told what public means.
    (_) => const <PrivacyZone>[],
  );
  if (!context.mounted) return false;

  final hasZone = zones.isNotEmpty;
  final theme = Theme.of(context);

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.public_rounded),
      title: const Text('Everyone can see this walk'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A public walk appears in Explore, where any member can open it — '
            'including people you have never met. They will see the route you '
            'took.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hasZone
                ? 'Your privacy zone is already trimming the ends of your '
                      'routes, so a walk that starts at home does not start '
                      'there for anyone else.'
                : 'Most walks start and finish at home. A privacy zone trims '
                      'those ends off before anyone else receives the route — '
                      'it takes about a minute to set one up.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not yet'),
        ),
        if (!hasZone)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              context.pushNamed(Routes.privacyZones);
            },
            child: const Text('Set a zone first'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Make it public'),
        ),
      ],
    ),
  );

  if (accepted ?? false) {
    // Only on acceptance. Somebody who chose "Not yet" has not been told
    // anything they should be assumed to remember.
    await ref.read(privacyActionsProvider).markPublicNoticeSeen();
    return true;
  }
  return false;
}

/// The current setting, as a small pill. Used on a walk's own card and detail
/// header so the audience is visible without opening anything.
class VisibilityChip extends StatelessWidget {
  const VisibilityChip({super.key, required this.visibility, this.onTap});

  final ActivityVisibility visibility;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.chip,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            visibilityIcon(visibility),
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(visibility.label, style: theme.textTheme.labelSmall),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Visible to ${visibility.label}. Change who can see this walk.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chip,
        child: content,
      ),
    );
  }
}

/// Changing a saved walk's audience, from the walk itself.
///
/// A sheet rather than a screen: the decision is three options wide and the
/// walk should stay behind it.
Future<ActivityVisibility?> showVisibilitySheet(
  BuildContext context, {
  required ActivityVisibility current,
}) {
  return showModalBottomSheet<ActivityVisibility>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Who can see this walk',
              subtitle: 'You can change this at any time.',
            ),
            Consumer(
              builder: (context, ref, _) => VisibilityPicker(
                value: current,
                onChanged: (chosen) => Navigator.of(context).pop(chosen),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
