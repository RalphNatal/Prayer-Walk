import 'feed_entry.dart';

abstract interface class FeedRepository {
  /// Activities from the people [viewerId] follows, plus their own, newest
  /// first. Empty list is a valid, expected result.
  ///
  /// [before] is a keyset cursor: pass the `startedAt` of the last entry on
  /// screen to read the page behind it. The feed screen loads one page today;
  /// the parameter is here so adding the second one is not a schema change.
  Future<List<FeedEntry>> feedFor(
    String viewerId, {
    DateTime? before,
    int limit,
  });
}
