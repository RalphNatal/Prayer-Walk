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

  /// Public walks from members [viewerId] does not follow, newest first.
  ///
  /// The one read in the app that deliberately reaches past the follow graph,
  /// which is exactly why it is the one place a visibility mistake would
  /// publish a stranger's route to the whole membership. `explore_feed` filters
  /// on `visibility = 'public'` explicitly rather than trusting recency, and
  /// the SELECT policy on `activities` has already removed everything else.
  ///
  /// Empty is an ordinary result: it means nobody has chosen to walk publicly
  /// yet, not that anything failed.
  Future<List<FeedEntry>> exploreFor(
    String viewerId, {
    DateTime? before,
    int limit,
  });
}
