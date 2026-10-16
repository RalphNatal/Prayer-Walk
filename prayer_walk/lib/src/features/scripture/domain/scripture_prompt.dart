import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'bible_translation.dart';

/// What a prompt is. Both arrive the same way on a walk; the distinction is
/// only in how they read and whether a translation is credited.
enum ScripturePromptKind {
  scripture('Scripture'),
  prayer('Prayer');

  const ScripturePromptKind(this.label);
  final String label;
}

/// One passage or short prayer, short enough to take in at a glance or in a
/// single spoken breath while walking.
///
/// The in-motion counterpart to [Devotional]: same admin-curated origin, same
/// [DevotionalCategory] themes — deliberately the existing enum rather than a
/// parallel one, so a "Stillness" walk and a "Stillness" devotional mean the
/// same thing — but sized for a phone in a pocket rather than a reader page.
///
/// [translation] carries the edition the text came from ("WEBBE", "NLT"). It is
/// resolved to a [BibleTranslation] — the terms, not just a label — so the UI
/// credits whatever is actually on screen and cannot render a licensed verse
/// without its mark. Prayers carry an empty translation: nothing is being
/// quoted, so nothing is credited.
class ScripturePrompt {
  const ScripturePrompt({
    required this.id,
    required this.reference,
    required this.body,
    required this.category,
    this.translation = '',
    this.kind = ScripturePromptKind.scripture,
    this.sortOrder = 0,
    this.isPublished = true,
    this.contributorName = '',
    this.groupId,
    this.groupName = '',
  });

  final String id;

  /// `Psalm 121:1-2` for scripture; the prayer's name for a prayer.
  final String reference;

  /// The verse or prayer text itself.
  final String body;

  final String translation;
  final ScripturePromptKind kind;
  final DevotionalCategory category;
  final int sortOrder;

  /// Whether this is live on walks.
  ///
  /// Defaults to true because almost every prompt that reaches this class is
  /// already published: `publishedPrompts` filters server-side, and the offline
  /// cache and the bundled asset only ever hold published verses. It matters on
  /// exactly one path — the admin list, which asks for drafts too.
  final bool isPublished;

  /// C3 · Who proposed this, when a member did.
  ///
  /// Empty for the admin-curated library, which is the church speaking rather
  /// than a person and is not attributed to one. Present for anything that came
  /// through the submissions queue, and it keeps travelling: the arrival card
  /// on a walk credits the contributor beside the same quotation that carries
  /// the translation mark. Losing provenance would turn a church's own
  /// contributions back into anonymous content.
  final String contributorName;

  bool get hasContributor => contributorName.trim().isNotEmpty;

  /// The church group this came from, or null for the global library.
  ///
  /// A group's prompts reach only its active members, and only ever in the
  /// public domain or as a prayer — the database holds that line
  /// (`scripture_prompts_group_rows_public_domain`). They are delivered
  /// whatever edition the build is configured for: the group chose them, and
  /// there is no licensed version of a group's own verse to prefer.
  final String? groupId;

  /// "St Anne" — credited under the verse, so a walker knows it came from
  /// their church rather than from the app. Empty for the global library, and
  /// for a group the cache did not know the name of.
  final String groupName;

  bool get isFromGroup => groupId != null && groupId!.isNotEmpty;

  /// Whether there is any text at all behind the reference.
  ///
  /// A member may submit a reference on its own and let a moderator match it to
  /// text the library already holds, so an empty [body] is an ordinary state
  /// rather than a broken row. Screens ask this instead of reading [body]
  /// directly — reaching for the raw text outside the seam is what
  /// `scripture_attribution_test.dart` exists to refuse, and "is there
  /// anything here" is a question that does not need the text to answer.
  bool get hasBody => body.trim().isNotEmpty;

  /// Whether there is an edition to credit alongside the text.
  bool get hasTranslation => translation.trim().isNotEmpty;

  /// The terms this text comes with. An edition this build has never heard of
  /// resolves to [BibleTranslation.unknown], which requires a mark — the safe
  /// direction to be wrong in.
  BibleTranslation get translationInfo => BibleTranslation.of(translation);

  /// **The text, as it may be shown.** Every display path uses this rather than
  /// [body]: the required `(NLT)`-style mark is part of the quotation, not a
  /// decoration a screen can decide to leave off. [body] stays raw for the
  /// admin editor and the row mappers, which write the column rather than
  /// display it.
  String get attributedBody => translationInfo.attributed(body);

  /// What a screen reader and the voice both say. The reference first, so an
  /// announcement is placeable before it is understood — and the mark last,
  /// because a spoken quotation is still a quotation.
  String get spoken => '$reference. $attributedBody';
}
