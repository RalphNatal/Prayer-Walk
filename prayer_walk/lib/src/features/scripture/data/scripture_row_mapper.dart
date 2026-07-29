import '../../devotionals/data/devotional_row_mapper.dart'
    show devotionalCategoryFrom;
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/scripture_prompt.dart';
import '../domain/scripture_submission.dart';

/// Row ⇄ [ScripturePrompt], in one place — the same bargain
/// `activity_row_mapper.dart` makes.
///
/// The bundled JSON asset and the local cache use this shape too, on purpose:
/// one mapper serves the table, the offline floor and the last-synced copy, so
/// the three cannot drift into disagreeing about what a prompt is.

/// The `scripture_prompts` columns a read needs. Kept next to the mapper so the
/// two cannot fall out of step.
const scripturePromptColumns =
    'id, reference, body, translation, kind, category, sort_order, '
    'is_published, status, submitted_by, contributor_note, rejection_reason, '
    'reviewed_at, created_at, '
    // C3 · The contributor rides along with the verse rather than costing a
    // second request on a trail. The constraint is named because
    // `scripture_prompts` now reaches `profiles` twice — contributor and
    // reviewer — and PostgREST cannot tell them apart without being told.
    'contributor:profiles!scripture_prompts_submitted_by_fkey(full_name)';

ScripturePrompt scripturePromptFromRow(Map<String, dynamic> row) {
  return ScripturePrompt(
    id: (row['id'] ?? '').toString(),
    reference: (row['reference'] as String?)?.trim() ?? '',
    body: (row['body'] as String?)?.trim() ?? '',
    translation: (row['translation'] as String?)?.trim() ?? '',
    kind: _kindFrom(row['kind'] as String?),
    category: categoryFrom(row['category'] as String?),
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    // Absent in a cache written before this key existed, and absent from the
    // bundled asset — both of which only ever hold published prompts, so the
    // missing key reads as true rather than hiding the offline library.
    isPublished: row['is_published'] != false,
    contributorName: contributorNameFrom(row),
  );
}

/// The contributor's name, from either row shape.
///
/// A row from Supabase carries a nested `contributor` object; the local cache
/// and the bundled asset flatten it to `contributor_name`, because a cache does
/// not need a join to write back what it already knows. Both arrive here so the
/// three sources cannot disagree about who wrote something.
String contributorNameFrom(Map<String, dynamic> row) {
  final embedded = row['contributor'];
  if (embedded is Map) {
    final name = (embedded['full_name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;
    // Submitted by somebody who has not set a name. "A member" is true, and
    // better than an empty byline that reads as admin-curated.
    return 'A member';
  }
  return (row['contributor_name'] as String?)?.trim() ?? '';
}

/// Rows to prompts, dropping anything that has no text to show. A malformed
/// row is one fewer verse, never a failed walk.
List<ScripturePrompt> scripturePromptsFromRows(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map)
      scripturePromptFromRow(Map<String, dynamic>.from(row)),
].where((p) => p.body.isNotEmpty && p.reference.isNotEmpty).toList();

/// The inverse, for writing the last-synced set to the local cache.
Map<String, dynamic> scripturePromptToRow(ScripturePrompt prompt) => {
  'id': prompt.id,
  'reference': prompt.reference,
  'body': prompt.body,
  'translation': prompt.translation,
  'kind': prompt.kind.name,
  'category': prompt.category.name,
  'sort_order': prompt.sortOrder,
  'is_published': prompt.isPublished,
  // Flattened rather than re-nested: the cache is written from a domain object
  // that has already resolved the join, and a walk offline should still credit
  // the person who contributed the verse it is reading.
  'contributor_name': prompt.contributorName,
};

/// A queue row → [ScriptureSubmission]: the prompt, plus everything the review
/// process wrote around it.
///
/// Same row shape as [scripturePromptFromRow] reads — one select serves the
/// library, the member's own list of what they sent, and the admin queue, so
/// the three cannot come to disagree about what a submission is.
ScriptureSubmission scriptureSubmissionFromRow(Map<String, dynamic> row) {
  final submittedBy = (row['submitted_by'] as String?)?.trim();
  return ScriptureSubmission(
    prompt: scripturePromptFromRow(row),
    status: SubmissionStatus.fromWire(row['status'] as String?),
    contributorId: (submittedBy?.isEmpty ?? true) ? null : submittedBy,
    contributorName: contributorNameFrom(row),
    reflection: (row['contributor_note'] as String?)?.trim() ?? '',
    rejectionReason: (row['rejection_reason'] as String?)?.trim() ?? '',
    reviewedAt: DateTime.tryParse(
      (row['reviewed_at'] as String?) ?? '',
    )?.toLocal(),
    submittedAt: DateTime.tryParse(
      (row['created_at'] as String?) ?? '',
    )?.toLocal(),
  );
}

/// Shared with the settings store, which persists the chosen theme by name.
///
/// One definition, in the devotionals mapper, because a theme means the same
/// thing on `devotionals` and `scripture_prompts` and a second copy is how the
/// two would eventually disagree.
DevotionalCategory categoryFrom(String? value) => devotionalCategoryFrom(value);

ScripturePromptKind _kindFrom(String? value) =>
    ScripturePromptKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => ScripturePromptKind.scripture,
    );
