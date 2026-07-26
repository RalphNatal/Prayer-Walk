/// Admin-curated groupings. The member browses by these; the admin assigns one
/// on the content form.
enum DevotionalCategory {
  morningLight('Morning light', 'For the first walk of the day'),
  gratitude('Gratitude', 'Notice what has already been given'),
  intercession('Intercession', 'Carry someone else a while'),
  lament('Lament', 'For the walks that are heavy'),
  stillness('Stillness', 'Fewer words, slower steps'),
  scriptureWalk('Scripture walk', 'One passage, one route');

  const DevotionalCategory(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// A devotional or prayer prompt. Written and published by an admin, read by
/// members, and optionally carried into an activity.
class Devotional {
  const Devotional({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.category,
    required this.authorName,
    required this.updatedAt,
    required this.isPublished,
    this.scriptureRef = '',
    this.scriptureText = '',
    this.publishedAt,
    this.readMinutes = 3,
  });

  final String id;
  final String title;

  /// One line shown on the browse card.
  final String summary;

  /// The reader body. Paragraphs separated by a blank line.
  final String body;

  /// e.g. `Psalm 121:1-2`. Empty when the prompt carries no passage.
  final String scriptureRef;
  final String scriptureText;
  final DevotionalCategory category;
  final String authorName;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final bool isPublished;
  final int readMinutes;

  bool get hasScripture => scriptureRef.isNotEmpty;

  Devotional copyWith({
    String? title,
    String? summary,
    String? body,
    String? scriptureRef,
    String? scriptureText,
    DevotionalCategory? category,
    bool? isPublished,
    DateTime? updatedAt,
    DateTime? publishedAt,
    int? readMinutes,
  }) {
    return Devotional(
      id: id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      body: body ?? this.body,
      category: category ?? this.category,
      authorName: authorName,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublished: isPublished ?? this.isPublished,
      scriptureRef: scriptureRef ?? this.scriptureRef,
      scriptureText: scriptureText ?? this.scriptureText,
      publishedAt: publishedAt ?? this.publishedAt,
      readMinutes: readMinutes ?? this.readMinutes,
    );
  }
}

/// The editable payload behind the admin create/edit form.
class DevotionalDraft {
  const DevotionalDraft({
    this.id,
    this.title = '',
    this.summary = '',
    this.body = '',
    this.scriptureRef = '',
    this.scriptureText = '',
    this.category = DevotionalCategory.morningLight,
    this.isPublished = false,
  });

  DevotionalDraft.from(Devotional d)
    : id = d.id,
      title = d.title,
      summary = d.summary,
      body = d.body,
      scriptureRef = d.scriptureRef,
      scriptureText = d.scriptureText,
      category = d.category,
      isPublished = d.isPublished;

  /// Null when creating.
  final String? id;
  final String title;
  final String summary;
  final String body;
  final String scriptureRef;
  final String scriptureText;
  final DevotionalCategory category;
  final bool isPublished;

  DevotionalDraft copyWith({
    String? title,
    String? summary,
    String? body,
    String? scriptureRef,
    String? scriptureText,
    DevotionalCategory? category,
    bool? isPublished,
  }) {
    return DevotionalDraft(
      id: id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      body: body ?? this.body,
      scriptureRef: scriptureRef ?? this.scriptureRef,
      scriptureText: scriptureText ?? this.scriptureText,
      category: category ?? this.category,
      isPublished: isPublished ?? this.isPublished,
    );
  }
}
