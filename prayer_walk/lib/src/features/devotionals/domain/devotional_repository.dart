import 'devotional.dart';

abstract interface class DevotionalRepository {
  /// What members browse: published only, grouped by the caller.
  Future<List<Devotional>> published({DevotionalCategory? category});

  /// What the admin content list shows: drafts included.
  Future<List<Devotional>> all();

  Future<Devotional> byId(String id);

  /// Create when [draft.id] is null, otherwise update in place.
  Future<Devotional> save(DevotionalDraft draft, {required String authorName});

  Future<Devotional> setPublished(String id, {required bool published});

  Future<void> delete(String id);
}
