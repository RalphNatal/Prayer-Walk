import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'scripture_library.dart';
import 'scripture_prompt.dart';
import 'scripture_submission.dart';

/// The prompt library.
///
/// [publishedPrompts] is the only method a walk needs, and it is the one that
/// must never fail: a walk happens outdoors, often with no signal, and losing
/// the network must cost verses at worst, never the recording. Implementations
/// are expected to fall back rather than throw.
///
/// The curation methods are the admin content screens' seam. Until this phase
/// the seed SQL was the only way to add a verse; they are now wired to a real
/// screen, and scoped by the table's admin policy either way.
abstract interface class ScriptureRepository {
  /// What a walk reads from. Never throws; returns the best set it can reach.
  Future<List<ScripturePrompt>> publishedPrompts({DevotionalCategory? category});

  /// The same set, plus where it came from and which edition was asked for.
  ///
  /// A walk does not need this — [publishedPrompts] is the verses, and verses
  /// are all a walk wants. The diagnostic readout does: "these are not the
  /// verses I configured" has several possible causes, and the only one visible
  /// from the text itself is the wrong edition being seeded. Knowing whether
  /// the set arrived from the network, from the last sync, or from the asset
  /// inside the binary separates the rest of them without a code trace.
  ///
  /// Same contract as [publishedPrompts]: never throws, always answers.
  Future<ScriptureLibrary> publishedLibrary({DevotionalCategory? category});

  // ------------------------------------------------------- admin curation ---

  /// Drafts included. Admin-only by RLS.
  Future<List<ScripturePrompt>> allPrompts();

  /// Create when [draft.id] is null, otherwise update in place.
  Future<ScripturePrompt> savePrompt(ScripturePromptDraft draft);

  Future<ScripturePrompt> setPublished(String id, {required bool published});

  Future<void> deletePrompt(String id);

  // ------------------------------------------------- member contributions ---

  /// C1 · Sends a member's proposal into the queue.
  ///
  /// Always lands as `pending` and never published. That is enforced by the
  /// insert policy rather than by this method: there is no member UPDATE policy
  /// on `scripture_prompts` at all, so there is no path — bug, malice or
  /// otherwise — by which a submission publishes itself into other people's
  /// walks.
  Future<void> submitPrompt(ScriptureSubmissionDraft draft);

  /// What the signed-in member has sent, whatever became of it. Rejections
  /// included, with their reason: a queue that swallows submissions silently
  /// teaches people to stop sending them.
  Future<List<ScriptureSubmission>> mySubmissions();

  // ---------------------------------------------------------- admin queue ---

  /// The submissions queue. Admin-only by RLS.
  Future<List<ScriptureSubmission>> submissions({SubmissionStatus? status});

  /// Approves or rejects, and — on approval — publishes.
  ///
  /// [reason] is recorded on a rejection so the contributor is told something
  /// rather than nothing. `reviewed_by` and `reviewed_at` are stamped by a
  /// trigger rather than sent from here, so a decision cannot end up in the
  /// record with nobody's name on it.
  Future<void> reviewSubmission(
    String id, {
    required SubmissionStatus outcome,
    String reason = '',
  });
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

  ScripturePromptDraft.from(ScripturePrompt prompt)
    : id = prompt.id,
      reference = prompt.reference,
      body = prompt.body,
      translation = prompt.translation,
      kind = prompt.kind,
      category = prompt.category,
      sortOrder = prompt.sortOrder,
      isPublished = prompt.isPublished;

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
