import '../domain/devotional.dart';

/// Row ⇄ [Devotional], in one place — the bargain `activity_row_mapper.dart`
/// and `profile_row_mapper.dart` already make.
///
/// The member shelf, the reader and the admin content list all read the same
/// row through this, so a devotional cannot mean one thing on the shelf and
/// another in the console.

/// The `devotionals` columns every read selects. Kept next to the mapper so the
/// two cannot fall out of step.
const devotionalColumns =
    'id, title, summary, body, scripture_ref, scripture_text, translation, '
    'category, author_id, author_name, read_minutes, is_published, '
    'published_at, updated_at';

Devotional devotionalFromRow(Map<String, dynamic> row) {
  final authorName = (row['author_name'] as String?)?.trim() ?? '';

  return Devotional(
    id: (row['id'] ?? '').toString(),
    title: (row['title'] as String?)?.trim() ?? '',
    summary: (row['summary'] as String?)?.trim() ?? '',
    body: (row['body'] as String?) ?? '',
    scriptureRef: (row['scripture_ref'] as String?)?.trim() ?? '',
    scriptureText: (row['scripture_text'] as String?)?.trim() ?? '',
    // Nullable in the database and absent from a row read before
    // `20260728070000_devotional_translation.sql` was applied. Empty means
    // "nothing to credit", which is the right answer for a devotional with no
    // passage and the safe answer for one written before the column existed —
    // everything from that era is WEBBE, which owes nothing either way.
    translation: (row['translation'] as String?)?.trim() ?? '',
    category: devotionalCategoryFrom(row['category'] as String?),
    // A devotional outlives the account that wrote it — `author_id` is set to
    // null on delete, and the byline falls back rather than going blank.
    authorName: authorName.isEmpty ? 'Prayer Walk' : authorName,
    updatedAt: _time(row['updated_at']) ?? DateTime.now(),
    publishedAt: _time(row['published_at']),
    isPublished: row['is_published'] == true,
    readMinutes: (row['read_minutes'] as num?)?.toInt() ?? 3,
  );
}

List<Devotional> devotionalsFromRows(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map) devotionalFromRow(Map<String, dynamic>.from(row)),
];

/// The `category` column carries the enum's *value name*, not its label — the
/// same convention `scripture_prompts.category` uses, so one theme means one
/// thing on both tables. An unrecognised value reads as stillness rather than
/// failing the shelf.
DevotionalCategory devotionalCategoryFrom(String? value) =>
    DevotionalCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => DevotionalCategory.stillness,
    );

/// ~200 words a minute, floor of one.
///
/// Derived rather than asked for: the admin form has enough fields already, and
/// a number nobody maintains is a number that goes stale.
int estimateReadMinutes(String body) {
  final words = body
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  return (words / 200).ceil().clamp(1, 60);
}

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
