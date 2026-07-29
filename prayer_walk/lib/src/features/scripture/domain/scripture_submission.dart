import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'bible_translation.dart';
import 'scripture_prompt.dart';

/// Where a proposed prompt is in review.
///
/// Nothing reaches a walk without passing through `approved` and being
/// published by an admin — a scripture prompt is delivered *into somebody
/// else's walk*, unasked, while they are outdoors and half-attending, and that
/// is not a channel a stranger gets to write to directly.
enum SubmissionStatus {
  pending('Waiting', 'Waiting for a moderator to read it.'),
  approved('Approved', 'Approved. It may be delivered on walks.'),
  rejected('Not used', 'A moderator decided not to use this one.');

  const SubmissionStatus(this.label, this.description);

  final String label;
  final String description;

  static SubmissionStatus fromWire(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    for (final status in values) {
      if (status.name == key) return status;
    }
    // An unknown status is not approved. Failing towards "not published" is the
    // only direction that cannot put unreviewed text on somebody's walk.
    return SubmissionStatus.pending;
  }
}

/// What a member sends: a reference, a theme, and their own words.
///
/// ⚖️ **The shape of this class is the licensing guard.**
///
/// Tyndale permit up to 500 NLT verses without written permission. A curated
/// admin set of about fifty sits comfortably inside that; an open submissions
/// form does not, and a parish pasting NLT passages would pass the ceiling in a
/// season with nobody counting. So a member does not paste scripture.
///
/// [reference] names a passage. [reflection] is the member's own prayer or
/// note, which is unambiguously theirs to give and is licensed from nobody.
/// [body] is the one field that can carry verse text, it is optional, and it is
/// **public-domain only** — the insert policy in
/// `20260728110000_scripture_submissions.sql` refuses any other translation
/// outright, so this is a rule the database keeps rather than a request the
/// form makes politely.
class ScriptureSubmissionDraft {
  const ScriptureSubmissionDraft({
    this.reference = '',
    this.body = '',
    this.reflection = '',
    this.kind = ScripturePromptKind.scripture,
    this.category = DevotionalCategory.stillness,
  });

  /// 'Psalm 121:1-2', or the name of a prayer.
  final String reference;

  /// Optional, and WEBBE only. Left empty, the prompt carries the reference and
  /// whatever text the library already holds for it.
  final String body;

  /// The member's own reflection or prayer. The part of a submission that is
  /// actually theirs, and the part the form is really about.
  final String reflection;

  final ScripturePromptKind kind;
  final DevotionalCategory category;

  /// The only translation a member may submit text under.
  ///
  /// Public domain: no fee, no permission, no ceiling, and nothing to count.
  static const allowedTranslation = BibleTranslation.webbe;

  /// Said inline on the form, next to the field it governs. Not in a help page
  /// and not in a checkbox nobody reads.
  static const licenceNote =
      'Only public-domain text may be typed here — the World English Bible '
      '(WEBBE), which is free of copyright. Do not paste from the NLT, NIV, '
      'ESV, NASB or CSB: those are licensed, and this app cannot carry them '
      'from an open form. If you leave it blank, the reference alone is '
      'enough — a moderator will match it to text the app already holds.';

  ScriptureSubmissionDraft copyWith({
    String? reference,
    String? body,
    String? reflection,
    ScripturePromptKind? kind,
    DevotionalCategory? category,
  }) => ScriptureSubmissionDraft(
    reference: reference ?? this.reference,
    body: body ?? this.body,
    reflection: reflection ?? this.reflection,
    kind: kind ?? this.kind,
    category: category ?? this.category,
  );
}

/// A submitted prompt as it appears in a queue — the prompt, its status, and
/// who proposed it.
///
/// C3 · The contributor's name travels with it and keeps travelling: an
/// approved submission renders its contributor beside the verse, alongside the
/// translation mark the quotation already carries. Provenance is not decoration
/// in a member-contributed library — it is half of what makes it read as a
/// parish rather than as a content feed.
class ScriptureSubmission {
  const ScriptureSubmission({
    required this.prompt,
    required this.status,
    this.contributorName = '',
    this.contributorId,
    this.reflection = '',
    this.rejectionReason = '',
    this.reviewedAt,
    this.submittedAt,
  });

  final ScripturePrompt prompt;
  final SubmissionStatus status;

  /// Empty for the admin-curated rows that predate submissions, which have no
  /// contributor and are not attributed to one.
  final String contributorName;
  final String? contributorId;

  final String reflection;
  final String rejectionReason;
  final DateTime? reviewedAt;
  final DateTime? submittedAt;

  bool get isMemberContributed => contributorId != null;

  /// How many verses this submission would spend against Tyndale's ceiling.
  ///
  /// Zero unless it carries licensed text — which a member's cannot, and an
  /// admin's can only after the admin has changed the translation deliberately.
  /// That is the number the queue shows before anything is approved.
  int get licensedVerseCost => prompt.translationInfo.requiresAttribution
      ? approximateVerseCount(prompt.reference)
      : 0;
}
