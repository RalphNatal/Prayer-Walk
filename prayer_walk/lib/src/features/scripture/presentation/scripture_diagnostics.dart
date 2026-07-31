import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../data/scripture_providers.dart';
import '../domain/bible_translation.dart';
import '../domain/scripture_library.dart';

/// Which translation this build is actually serving, and where it got it.
///
/// This exists because the question "why are these not the verses I
/// configured?" cost a full trace through five files to answer, and every one
/// of the plausible causes — the licensed rows were never seeded, the default
/// still says something else, the filter is not filtering, the device fell back
/// to the asset in the binary — is visible in these three lines.
///
/// **Debug builds only.** It builds to nothing in release, because it is a
/// maintainer's readout and not a feature: a walker does not need to know what
/// a cache is, and the honest half of this — the credit under every passage —
/// ships to them instead.
class ScriptureDiagnostics extends ConsumerWidget {
  const ScriptureDiagnostics({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final configured = ref.watch(appTranslationProvider);
    final library = ref.watch(loadedScriptureLibraryProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Translation diagnostic  ·  debug builds only',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Cause 2: the build is configured for an edition nobody changed.
          _Line(
            label: 'Configured default',
            value: '${configured.id}  (SCRIPTURE_TRANSLATION)',
          ),

          library.when(
            loading: () => const _Line(label: 'Library', value: 'loading…'),
            error: (error, _) => _Line(
              label: 'Library',
              value: 'failed: ${error.runtimeType}',
            ),
            data: (loaded) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cause 4: the device is reading the asset in the binary, which
                // is WEBBE by design and cannot be anything else.
                _Line(label: 'Loaded from', value: loaded.source.label),
                // Causes 1 and 3: whether the licensed rows exist at all, and
                // whether the filter narrowed to them.
                _Line(label: 'Available', value: _counts(loaded)),
                _Line(label: 'Delivering', value: _delivering(loaded)),
                if (loaded.fellBack) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'No ${loaded.requested.id} passages were found, so the '
                    'whole library is being delivered instead. Each verse still '
                    'carries its own credit.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (loaded.source == ScriptureLibrarySource.bundled) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The bundled asset is public-domain '
                    '${BibleTranslation.fallback.id} and stays that way. '
                    'Nothing licensed ships inside the binary.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 'WEBBE 301 · NLT 0 · prayers 18' — the line that answers the complaint.
  ///
  /// Every edition the app knows about is listed whether or not it has rows,
  /// because a zero is the informative value here: an absent row for NLT reads
  /// as "not seeded yet", and an absent *line* reads as nothing at all.
  static String _counts(ScriptureLibrary loaded) {
    final counts = loaded.countsByTranslation;
    final parts = <String>[
      for (final translation in BibleTranslation.values)
        '${translation.shortCode} ${counts[translation.shortCode] ?? 0}',
      for (final entry in counts.entries)
        if (entry.key.isNotEmpty &&
            !BibleTranslation.values.any((t) => t.shortCode == entry.key))
          '${entry.key} ${entry.value}',
      if ((counts[''] ?? 0) > 0) 'prayers ${counts['']}',
    ];
    return parts.join('  ·  ');
  }

  static String _delivering(ScriptureLibrary loaded) {
    final editions = loaded.deliveredTranslations.map((t) => t.id).toList()
      ..sort();
    if (editions.isEmpty) return 'no quotations — prayers only';
    return '${editions.join(', ')}  (${loaded.prompts.length} prompts)';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
