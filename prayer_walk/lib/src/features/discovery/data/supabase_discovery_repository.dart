import '../../../core/supabase/supabase_client.dart';
import '../../profile/data/profile_row_mapper.dart';
import '../domain/discovery_repository.dart';
import '../domain/member_card.dart';

/// Search and suggestions, from `search_members` and `suggested_members`.
///
/// Both are `security invoker`, so the policies on `profiles` and `activities`
/// still apply inside them: a suspended member, or one either party has
/// blocked, is absent because the database removed them and not because this
/// class filtered afterwards. What the functions add is intent — how to rank a
/// name match, what counts as recently active — never reach.
class SupabaseDiscoveryRepository implements DiscoveryRepository {
  const SupabaseDiscoveryRepository(this._viewerId);

  final String? _viewerId;

  @override
  Future<List<MemberCard>> searchMembers(String query, {int limit = 20}) async {
    final viewerId = _viewerId;
    final term = query.trim();
    // Not a round trip for an empty field. The SQL returns nothing for a blank
    // term too — this is the same answer, arrived at without waking the
    // network on every keystroke back to nothing.
    if (viewerId == null || term.isEmpty) return const [];

    final rows =
        await supabase.rpc(
              'search_members',
              params: {
                'query': term,
                'viewer': viewerId,
                'limit_count': limit,
              },
            )
            as List<dynamic>;

    return memberCardsFromRows(rows);
  }

  @override
  Future<List<MemberCard>> suggestedMembers({int limit = 8}) async {
    final viewerId = _viewerId;
    if (viewerId == null) return const [];

    final rows =
        await supabase.rpc(
              'suggested_members',
              params: {'viewer': viewerId, 'limit_count': limit},
            )
            as List<dynamic>;

    return memberCardsFromRows(rows);
  }
}

/// `member_card` rows → [MemberCard]s.
///
/// Split out from the calls so the mapping can be tested without a Postgres,
/// the way `feedEntriesFromRows` is. The nested `profile` object is the same
/// shape the feed's `author` is, and goes through the same mapper — a member
/// found by search and the same member seen on a card have to be one person.
List<MemberCard> memberCardsFromRows(List<dynamic> rows) => [
  for (final row in rows.cast<Map<String, dynamic>>())
    MemberCard(
      profile: userProfileFromRow(row['profile'] as Map<String, dynamic>),
      isFollowing: (row['is_following'] as bool?) ?? false,
      followerCount: (row['follower_count'] as num?)?.toInt() ?? 0,
      lastWalkedAt: DateTime.tryParse(
        (row['last_walked_at'] as String?) ?? '',
      )?.toLocal(),
    ),
];
