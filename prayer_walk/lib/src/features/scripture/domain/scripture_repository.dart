import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'scripture_prompt.dart';

/// The prompt library.
///
/// [publishedPrompts] is the only method a walk needs, and it is the one that
/// must never fail: a walk happens outdoors, often with no signal, and losing
/// the network must cost verses at worst, never the recording. Implementations
/// are expected to fall back rather than throw.
///
/// The curation methods are declared here so the admin content screens have a
/// seam to grow into. They are wired to real queries but nothing in the app
/// calls them yet — scripture curation is part of the admin de-mock, which is
/// still ahead.
abstract interface class ScriptureRepository {
  /// What a walk reads from. Never throws; returns the best set it can reach.
  Future<List<ScripturePrompt>> publishedPrompts({DevotionalCategory? category});

  // ------------------------------------------------------- admin curation ---

  /// Drafts included. Admin-only by RLS.
  Future<List<ScripturePrompt>> allPrompts();

  /// Create when [draft.id] is null, otherwise update in place.
  Future<ScripturePrompt> savePrompt(ScripturePromptDraft draft);

  Future<ScripturePrompt> setPublished(String id, {required bool published});

  Future<void> deletePrompt(String id);
}

/// The editable payload behind a future admin create/edit form. Mirrors
/// [DevotionalDraft] so the two content types feel like one system.
class ScripturePromptDraft {
  const ScripturePromptDraft({
    this.id,
    this.reference = '',
    this.body = '',
    this.translation = 'WEBBE',
    this.kind = ScripturePromptKind.scripture,
    this.category = DevotionalCategory.stillness,
    this.isPublished = false,
    this.sortOrder = 0,
  });

  ScripturePromptDraft.from(ScripturePrompt prompt, {this.isPublished = true})
    : id = prompt.id,
      reference = prompt.reference,
      body = prompt.body,
      translation = prompt.translation,
      kind = prompt.kind,
      category = prompt.category,
      sortOrder = prompt.sortOrder;

  /// Null when creating.
  final String? id;
  final String reference;
  final String body;
  final String translation;
  final ScripturePromptKind kind;
  final DevotionalCategory category;
  final bool isPublished;
  final int sortOrder;
}
