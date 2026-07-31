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
///
/// It no longer renders nothing. An edition that owes no mark used to leave the
/// credit line empty, and a blank line under a verse is indistinguishable from
/// a verse in some other edition entirely — which is the state that let a WEBBE
/// offline fallback pass unnoticed on a build configured for something else.
/// [BibleTranslation.creditLabel] always has something true to say, including
/// for a prayer that quotes nobody.
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
    return Text(
      long && translation.displayName.isNotEmpty
          ? translation.displayName
          : translation.creditLabel,
      style: style ?? Theme.of(context).textTheme.labelSmall,
    );
  }
}

/// A quotation that has outlived the column that named its edition.
///
/// One case, and it is worth naming precisely: a scripture waypoint's note. It
/// is JSONB on `activities` with no `translation` beside it, so by the time the
/// summary and detail lists draw it there is nothing left but a string. The
/// string is not silent — `RecordingController` writes it through
/// [BibleTranslation.attributed] at the one moment the edition is still known,
/// so a licensed quotation still carries its `(NLT)`.
///
/// This widget reads that mark back with [BibleTranslation.declaredIn] and
/// names the edition underneath, so a saved verse is as identifiable as a live
/// one. Where no mark was written the credit says so plainly rather than
/// guessing an edition — see [BibleTranslation.creditLabel].
///
/// The text itself is drawn exactly as stored: nothing here may add a mark,
/// because the stored string is the record of what was actually delivered.
class MarkedQuotation extends StatelessWidget {
  const MarkedQuotation({
    super.key,
    required this.markedText,
    this.style,
    this.creditStyle,
    this.showTranslation = true,
  });

  /// The persisted note, already attributed.
  final String markedText;

  final TextStyle? style;
  final TextStyle? creditStyle;

  /// The walker's preference about the courtesy credit. It governs the label
  /// under the text and nothing above it: a required mark is inside
  /// [markedText] itself, so no setting can reach it.
  final bool showTranslation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final declared = BibleTranslation.declaredIn(markedText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(markedText, style: style),
        if (showTranslation) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            declared.creditLabel,
            style: creditStyle ?? theme.textTheme.labelSmall,
          ),
        ],
      ],
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
