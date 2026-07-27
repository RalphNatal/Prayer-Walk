import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../domain/scripture_prompt.dart';

/// Row ⇄ [ScripturePrompt], in one place — the same bargain
/// `activity_row_mapper.dart` makes.
///
/// The bundled JSON asset and the local cache use this shape too, on purpose:
/// one mapper serves the table, the offline floor and the last-synced copy, so
/// the three cannot drift into disagreeing about what a prompt is.

/// The `scripture_prompts` columns a read needs. Kept next to the mapper so the
/// two cannot fall out of step.
const scripturePromptColumns =
    'id, reference, body, translation, kind, category, sort_order';

ScripturePrompt scripturePromptFromRow(Map<String, dynamic> row) {
  return ScripturePrompt(
    id: (row['id'] ?? '').toString(),
    reference: (row['reference'] as String?)?.trim() ?? '',
    body: (row['body'] as String?)?.trim() ?? '',
    translation: (row['translation'] as String?)?.trim() ?? '',
    kind: _kindFrom(row['kind'] as String?),
    category: categoryFrom(row['category'] as String?),
    sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
  );
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
};

/// Shared with the settings store, which persists the chosen theme by name.
DevotionalCategory categoryFrom(String? value) =>
    DevotionalCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => DevotionalCategory.stillness,
    );

ScripturePromptKind _kindFrom(String? value) =>
    ScripturePromptKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => ScripturePromptKind.scripture,
    );
