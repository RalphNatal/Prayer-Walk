import '../../devotionals/domain/devotional.dart' show DevotionalCategory;

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
/// [translation] carries the edition the text came from ("WEBBE"). It exists so
/// a licensed translation can be added later without a migration, and so the
/// UI can credit whatever is actually on screen. Prayers carry an empty
/// translation: nothing is being quoted, so nothing is credited.
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

  /// Whether there is an edition to credit alongside the text.
  bool get hasTranslation => translation.trim().isNotEmpty;

  /// What a screen reader and the voice both say. The reference first, so an
  /// announcement is placeable before it is understood.
  String get spoken => '$reference. $body';
}
