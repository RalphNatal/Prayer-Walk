import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../domain/bible_translation.dart';

/// **The only widget that draws quoted scripture.**
///
/// Every path that puts a verse on a screen goes through here: the arrival card
/// over the map, the expanded reading, the delivered list on the live screen,
/// the devotional reader, and the admin curation list. It exists so the
/// per-quotation mark a licensed translation requires — `(NLT)` — cannot be
/// forgotten by one screen while four others remember it. There is no parameter
/// to switch the mark off, because the licence does not offer one.
///
/// The one place the mark is applied outside this widget is the note written
/// onto a scripture waypoint, which is persisted rather than drawn — it goes
/// through the same [BibleTranslation.attributed] at the moment the text leaves
/// the prompt, so the summary and detail lists show a marked quotation without
/// having to know which edition dropped it. See `RecordingController`.
class ScriptureQuotation extends StatelessWidget {
  const ScriptureQuotation({
    super.key,
    required this.text,
    required this.translationId,
    this.style,
    this.maxLines,
    this.semanticsLabel,
  });

  /// The raw quotation. The mark is added here — callers pass the text as it
  /// sits in the row.
  final String text;

  /// The row's `translation` value, resolved to its terms here rather than by
  /// the caller.
  final String translationId;

  final TextStyle? style;

  /// Null reads in full; a number truncates, for a card over a map.
  final int? maxLines;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Text(
      BibleTranslation.of(translationId).attributed(text),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// The edition named under a passage — 'WEBBE', 'New Living Translation'.
///
/// Distinct from the mark: this is the courtesy credit the reading has always
/// drawn and which the walker can switch off in settings. The mark inside
/// [ScriptureQuotation] is not switchable, which is the difference that
/// matters — one is presentation, the other is a licence condition.
class TranslationCredit extends StatelessWidget {
  const TranslationCredit({
    super.key,
    required this.translationId,
    this.style,
    this.long = false,
  });

  final String translationId;
  final TextStyle? style;

  /// The full name rather than the initials, for a page with room for it.
  final bool long;

  @override
  Widget build(BuildContext context) {
    final translation = BibleTranslation.of(translationId);
    if (!translation.isQuotation) return const SizedBox.shrink();
    return Text(
      long && translation.displayName.isNotEmpty
          ? translation.displayName
          : translation.shortCode,
      style: style ?? Theme.of(context).textTheme.labelSmall,
    );
  }
}

/// The full notice for one translation, verbatim.
///
/// Used by the credits section in Settings. Nothing here reflows, paraphrases
/// or abbreviates the wording — for a licensed translation the text of the
/// notice is what the licence names, and [BibleTranslation.creditLine] is the
/// only place it is written down.
class TranslationCreditLine extends StatelessWidget {
  const TranslationCreditLine({super.key, required this.translation});

  final BibleTranslation translation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translation.displayName.isEmpty
                ? translation.id
                : translation.displayName,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            translation.creditLine.isNotEmpty
                ? translation.creditLine
                // An edition the build has no terms for. Say so plainly rather
                // than print an empty notice and look compliant.
                : 'This build does not carry the licence terms for '
                      '${translation.id}. Its text may only be published here '
                      'with permission from the copyright holder, and its '
                      'credit line must be added before release.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
