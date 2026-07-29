import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../data/scripture_settings_controller.dart';
import '../domain/scripture_settings.dart';
import 'scripture_library_progress.dart';

/// The one place scripture on the trail is configured.
///
/// Used twice, unchanged: inline in Settings as the standing default, and in a
/// sheet from the record screen as the choice for the walk about to start. It
/// is the same decision made at two moments, so it is the same control — and
/// because both write to the stored preference, a change made on the way out
/// of the door is still there next week.
class ScriptureSettingsPanel extends ConsumerWidget {
  const ScriptureSettingsPanel({super.key, this.showHeader = true});

  /// The sheet draws its own title; Settings uses a section header instead.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(scriptureSettingsProvider);
    final controller = ref.read(scriptureSettingsProvider.notifier);
    final cadence = settings.cadence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) ...[
          Text('Scripture on the trail', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A verse or a short prayer arrives every so often as you walk, and '
            'leaves a mark where it reached you.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text('Send verses as I walk', style: theme.textTheme.titleSmall),
          value: settings.enabled,
          onChanged: controller.setEnabled,
        ),

        if (settings.enabled) ...[
          const SizedBox(height: AppSpacing.md),
          Text('How often', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _IntervalChoices(settings: settings, controller: controller),

          if (_isCustom(cadence)) ...[
            const SizedBox(height: AppSpacing.sm),
            _CustomDistance(
              meters: cadence.intervalMeters,
              onChanged: controller.setIntervalMeters,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          Text('Measured by', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<CadenceSource>(
            segments: const [
              ButtonSegment(
                value: CadenceSource.distance,
                label: Text('Distance'),
              ),
              ButtonSegment(value: CadenceSource.steps, label: Text('Steps')),
            ],
            selected: {cadence.source},
            showSelectedIcon: false,
            onSelectionChanged: (choice) => controller.setSource(choice.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            cadence.source == CadenceSource.steps
                // Said plainly rather than discovered afterwards: this is the
                // option that asks for a permission and the one that some
                // phones cannot honour at all.
                ? 'Your phone will ask for motion access the first time you '
                      'start a walk this way. Where there is no step sensor, '
                      'the walk falls back to distance and says so.'
                : 'Distance is measured already, so this works on any phone '
                      'and while riding. Step figures shown here are '
                      'approximate — stride length varies.',
            style: theme.textTheme.bodySmall,
          ),

          const SizedBox(height: AppSpacing.lg),
          Text('Drawn from', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<DevotionalCategory?>(
            initialValue: settings.category,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem<DevotionalCategory?>(
                child: Text('Everything'),
              ),
              for (final category in DevotionalCategory.values)
                DropdownMenuItem<DevotionalCategory?>(
                  value: category,
                  child: Text(category.label),
                ),
            ],
            onChanged: controller.setCategory,
          ),

          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Chime', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'A soft tone on arrival. Silent mode is always respected.',
              style: theme.textTheme.bodySmall,
            ),
            value: settings.sound,
            onChanged: controller.setSound,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Read aloud', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'So a verse still reaches you with the phone in a pocket.',
              style: theme.textTheme.bodySmall,
            ),
            value: settings.voice,
            onChanged: controller.setVoice,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Show translation', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'Credits the edition under each passage.',
              style: theme.textTheme.bodySmall,
            ),
            value: settings.showTranslation,
            onChanged: controller.setShowTranslation,
          ),

          const SizedBox(height: AppSpacing.lg),
          // The sheet draws its own title and is opened on the way out of the
          // door; Settings is where an irreversible choice belongs.
          ScriptureLibraryProgress(allowReset: !showHeader),
        ],
      ],
    );
  }

  /// Whichever interval is not one of the two presets.
  static bool _isCustom(ScriptureCadence cadence) =>
      cadence.intervalMeters != ScriptureCadence.gentle.intervalMeters &&
      cadence.intervalMeters != ScriptureCadence.spacious.intervalMeters;
}

/// The two presets and the way out of them.
///
/// Each is labelled in both idioms — steps and metres — because the request was
/// made in steps and the measurement is made in metres, and hiding either half
/// of that would be the dishonest option.
class _IntervalChoices extends StatelessWidget {
  const _IntervalChoices({required this.settings, required this.controller});

  final ScriptureSettings settings;
  final ScriptureSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final cadence = settings.cadence;
    final custom = ScriptureSettingsPanel._isCustom(cadence);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _choice(
          context,
          label: 'About 500 steps',
          detail: '400 m',
          selected: !custom &&
              cadence.intervalMeters == ScriptureCadence.gentle.intervalMeters,
          onTap: () => controller.setCadence(
            ScriptureCadence.gentle.copyWith(source: cadence.source),
          ),
        ),
        _choice(
          context,
          label: 'About 1000 steps',
          detail: '800 m',
          selected: !custom &&
              cadence.intervalMeters == ScriptureCadence.spacious.intervalMeters,
          onTap: () => controller.setCadence(
            ScriptureCadence.spacious.copyWith(source: cadence.source),
          ),
        ),
        _choice(
          context,
          label: 'Custom',
          detail: custom ? '${cadence.intervalMeters.round()} m' : null,
          selected: custom,
          // Starts a step away from the nearest preset so the slider has
          // somewhere to be.
          onTap: () => controller.setIntervalMeters(600),
        ),
      ],
    );
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required String? detail,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(detail == null ? label : '$label  ·  $detail'),
    );
  }
}

class _CustomDistance extends StatelessWidget {
  const _CustomDistance({required this.meters, required this.onChanged});

  final double meters;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = (meters / kAverageStrideMeters).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: meters.clamp(200, 2000),
          min: 200,
          max: 2000,
          divisions: 18,
          label: '${meters.round()} m',
          semanticFormatterCallback: (value) =>
              'Every ${value.round()} metres',
          onChanged: onChanged,
        ),
        Text(
          'Every ${meters.round()} m — roughly $steps steps.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One line describing the current choice, for the record screen's tile.
String scriptureSummary(ScriptureSettings settings) {
  if (!settings.enabled) return 'Off';
  final cadence = settings.cadence;
  final every = cadence.source == CadenceSource.steps
      ? 'Every ${cadence.intervalSteps} steps'
      : 'Every ${cadence.intervalMeters.round()} m';
  final theme = settings.category?.label;
  return theme == null ? every : '$every  ·  $theme';
}

/// The record screen's way in. A sheet, so choosing a cadence never leaves the
/// screen the walker is about to start from.
Future<void> showScriptureSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: const ScriptureSettingsPanel(),
      ),
    ),
  );
}
