import 'feed_entry.dart';

abstract interface class FeedRepository {
  /// Activities from the people [viewerId] follows, plus their own, newest
  /// first. Empty list is a valid, expected result.
  Future<List<FeedEntry>> feedFor(String viewerId);
}
