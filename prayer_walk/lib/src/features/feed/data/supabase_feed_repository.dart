import '../../../core/supabase/supabase_client.dart';
import '../../activity/data/activity_row_mapper.dart';
import '../../profile/data/profile_row_mapper.dart';
import '../domain/feed_entry.dart';
import '../domain/feed_repository.dart';

/// The feed, from the real follow graph.
///
/// One `feed_for` call per page — the activity, its author and the two counts
/// all come back on the same row. The alternative, a select over `activities`
/// followed by a profile lookup and two count queries per card, is 61 requests
/// for 20 walks; a card is not worth a round trip.
class SupabaseFeedRepository implements FeedRepository {
  const SupabaseFeedRepository();

  @override
  Future<List<FeedEntry>> feedFor(
    String viewerId, {
    DateTime? before,
    int limit = 50,
  }) async {
    final rows =
        await supabase.rpc(
              'feed_for',
              params: {
                'viewer': viewerId,
                'limit_count': limit,
                'before': before?.toUtc().toIso8601String(),
              },
            )
            as List<dynamic>;

    return feedEntriesFromRows(rows);
  }
}

/// `activity_card` rows → [FeedEntry]s.
///
/// Split out from the call so the mapping can be tested without a Postgres.
/// An empty list in is an empty list out: someone who follows nobody and has
/// not walked yet has an empty feed, and that is a state, not a failure.
List<FeedEntry> feedEntriesFromRows(List<dynamic> rows) => [
  for (final row in rows.cast<Map<String, dynamic>>())
    FeedEntry(
      activity: activityFromRow(row),
      author: userProfileFromRow(row['author'] as Map<String, dynamic>),
    ),
];
