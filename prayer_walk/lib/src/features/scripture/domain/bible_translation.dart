/// A Bible translation, and what quoting it obliges this app to do.
///
/// `translation` used to be a passive string carried from a row to a label.
/// That was adequate while every verse was public domain and nothing was owed
/// to anybody. It is not adequate for a licensed translation, where the terms
/// are conditions of use rather than good manners: the New Living Translation
/// requires a credit line in the product and, in the short form, the initials
/// `(NLT)` at the end of *every* quotation.
///
/// So the obligation lives with the translation rather than with the screen.
/// A display path asks the translation what it owes and renders that; it cannot
/// render the text and forget the mark, because [attributed] is the only way to
/// get the text out. Adding a translation is adding a const below — no display
/// code changes, and no `if (id == 'NLT')` anywhere in the app.
library;

/// One edition, and its terms.
class BibleTranslation {
  const BibleTranslation({
    required this.id,
    required this.displayName,
    required this.shortCode,
    required this.requiresAttribution,
    required this.requiresQuotationMark,
    this.creditLine = '',
    this.isPublicDomain = false,
    this.isKnown = true,
  });

  /// A translation this build does not have terms for.
  ///
  /// Fails **closed**: an unrecognised edition is assumed to be licensed and
  /// assumed to require a mark, because the alternative — assuming a stranger
  /// is public domain — is the mistake that costs money. The mark is the id
  /// itself, so an editor who types `ESV` sees `(ESV)` on screen and a credits
  /// section that says out loud that this build does not know its terms.
  factory BibleTranslation.unknown(String id) => BibleTranslation(
    id: id,
    displayName: id,
    shortCode: id,
    requiresAttribution: true,
    requiresQuotationMark: true,
    isKnown: false,
  );

  /// What sits in `scripture_prompts.translation` / `devotionals.translation`.
  final String id;

  /// 'New Living Translation' — how it is named in prose and in the credits.
  final String displayName;

  /// 'NLT' — how it is named in a corner of a card.
  final String shortCode;

  /// Whether the full [creditLine] must appear in the app.
  final bool requiresAttribution;

  /// Whether `(NLT)`-style initials must follow every quotation.
  final bool requiresQuotationMark;

  /// The notice, verbatim. Never paraphrased, reflowed or abbreviated — for a
  /// licensed translation this is the wording the licence names, and for a
  /// public-domain one it is the courtesy note shown beside it.
  final String creditLine;

  final bool isPublicDomain;

  /// False for [BibleTranslation.unknown] — the credits surface says so rather
  /// than quietly presenting an empty notice as though nothing were owed.
  final bool isKnown;

  /// Whether this stands for an actual quotation. A prayer quotes nothing and
  /// carries an empty translation, so it credits nothing and marks nothing.
  bool get isQuotation => id.isNotEmpty;

  /// `(NLT)`. Empty when no mark is required.
  String get quotationMark => requiresQuotationMark ? '($shortCode)' : '';

  /// **The name a verse is shown under, always.**
  ///
  /// Distinct from [quotationMark], which only a licensed edition carries. This
  /// is what the credit under a passage says, and it is never empty: a walker
  /// should never have to guess which translation is being read, and "nothing
  /// shown" is exactly the state that let a WEBBE fallback pass for something
  /// else for as long as it did.
  ///
  /// A prayer quotes nobody, so it is named for what it is rather than left
  /// blank — the label is still true, and still tells the walker that no
  /// translation is involved.
  String get creditLabel => isQuotation ? shortCode : 'Public domain';

  /// **The only way a quotation becomes displayable text.**
  ///
  /// Every path that puts a verse on screen goes through here — the arrival
  /// card, the expanded reading, the live list, the devotional reader, the
  /// admin list, and the note written onto a scripture waypoint. Idempotent, so
  /// text that already carries its mark (a waypoint note read back from the
  /// database, say) is not marked twice.
  String attributed(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !requiresQuotationMark) return text;
    if (trimmed.endsWith(quotationMark)) return text;
    return '$trimmed $quotationMark';
  }

  // ------------------------------------------------------------- the set ---

  /// World English Bible, British Edition. Public domain: no fee, no permission
  /// and no obligation. It is the bundled offline set and the fallback, and it
  /// stays that way until permission covering a licensed translation *inside
  /// the shipped binary* is confirmed in writing.
  static const webbe = BibleTranslation(
    id: 'WEBBE',
    displayName: 'World English Bible, British Edition',
    shortCode: 'WEBBE',
    requiresAttribution: false,
    requiresQuotationMark: false,
    isPublicDomain: true,
    creditLine:
        'Scripture quotations marked WEBBE are taken from the World English '
        'Bible, British Edition, which is in the public domain.',
  );

  /// New Living Translation. Tyndale's terms are quoted in full in the README
  /// and in `supabase/seed/scripture_prompts_nlt_seed.sql.template`; the two
  /// that bind the app are the credit line below and, because Prayer Walk is
  /// non-salable media using the short form, the `(NLT)` after each quotation.
  static const nlt = BibleTranslation(
    id: 'NLT',
    displayName: 'New Living Translation',
    shortCode: 'NLT',
    requiresAttribution: true,
    requiresQuotationMark: true,
    creditLine:
        'Scripture quotations are taken from the Holy Bible, New Living '
        'Translation, copyright © 1996, 2004, 2015 by Tyndale House '
        'Foundation. Used by permission of Tyndale House Publishers, Carol '
        'Stream, Illinois 60188. All rights reserved.',
  );

  /// A prayer, or anything else quoting nobody.
  static const none = BibleTranslation(
    id: '',
    displayName: '',
    shortCode: '',
    requiresAttribution: false,
    requiresQuotationMark: false,
    isPublicDomain: true,
  );

  /// What an admin may choose from, and what the credits surface iterates.
  /// Adding a translation means adding a const above and a line here.
  static const values = <BibleTranslation>[webbe, nlt];

  /// The one used when nothing else says otherwise — and the one the app falls
  /// back to offline, whatever the configured default is.
  static const fallback = webbe;

  /// Row value → terms.
  ///
  /// `WEB` is accepted as [webbe]: it is the column default written by
  /// `20260727020000_scripture_prompts.sql`, from before the British edition
  /// was settled on, and both are the same public-domain text as far as any
  /// obligation goes. Matching ignores case and surrounding space, because a
  /// hand-typed `nlt` must not read as an unknown edition.
  static BibleTranslation of(String? id) {
    final key = (id ?? '').trim();
    if (key.isEmpty) return none;
    final upper = key.toUpperCase();
    if (upper == 'WEB') return webbe;
    for (final translation in values) {
      if (translation.id.toUpperCase() == upper) return translation;
    }
    return BibleTranslation.unknown(key);
  }

  /// The edition a piece of **already-marked** text declares about itself.
  ///
  /// The companion to [attributed], for the one place a quotation travels
  /// without its column: a scripture waypoint's note is JSONB on `activities`
  /// with no `translation` beside it, so what reaches the summary and detail
  /// lists is a bare string. That string is not silent, though — [attributed]
  /// wrote the mark into it at the moment the edition was still known, so a
  /// licensed quotation says `(NLT)` at its own end and can be read back here.
  ///
  /// Text carrying no mark resolves to [none], which is the truth rather than a
  /// guess: everything this app writes unmarked is either public-domain WEBBE
  /// or a prayer quoting nobody, and [creditLabel] names that honestly instead
  /// of inventing an edition for it.
  static BibleTranslation declaredIn(String markedText) {
    final trimmed = markedText.trim();
    final mark = RegExp(r'\(([A-Za-z0-9]{2,12})\)$').firstMatch(trimmed);
    if (mark == null) return none;
    final declared = of(mark.group(1));
    // Only a mark an edition would actually have written counts. `(NIV)` at the
    // end of a walker's own note is somebody typing, not this app attributing —
    // and `BibleTranslation.unknown` would otherwise turn any parenthesis into
    // a translation.
    return declared.requiresQuotationMark && declared.isKnown ? declared : none;
  }

  @override
  bool operator ==(Object other) =>
      other is BibleTranslation && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BibleTranslation($id)';
}

/// How many verses a reference stands for.
///
/// Tyndale's ceiling is counted in verses, not in rows: `1 Thessalonians
/// 5:16-18` is three of the five hundred, not one. Ranges are the only shape
/// this expands — a reference spanning chapters (`Psalm 22:31-23:1`) or listing
/// verses (`Psalm 1:1,3`) counts as one, which under-counts rather than over-,
/// so the number shown to an admin is a floor. It is a curation aid, not a
/// compliance certificate; the maintainer counts properly before going near
/// the limit.
int approximateVerseCount(String reference) {
  final trimmed = reference.trim();
  if (trimmed.isEmpty) return 0;
  final range = RegExp(r':\s*(\d+)\s*[-–]\s*(\d+)\s*$').firstMatch(trimmed);
  if (range == null) return 1;
  final from = int.parse(range.group(1)!);
  final to = int.parse(range.group(2)!);
  return to >= from ? to - from + 1 : 1;
}

/// Tyndale's limit for quoting the NLT without express written permission: up
/// to 500 verses, provided they are not more than 25% of the work and no
/// complete book of the Bible is quoted.
const int kNltVerseCeiling = 500;
