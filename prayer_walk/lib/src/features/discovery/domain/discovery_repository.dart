import 'member_card.dart';

/// How a member finds another member.
///
/// Two methods, and between them they are the whole door: type a name, or be
/// shown somebody who has walked publicly and recently. Everything else the
/// community already had — following, encouraging, commenting — was reachable
/// only by someone who already knew who to look for.
abstract interface class DiscoveryRepository {
  /// Members whose name, handle or parish matches [query], excluding the
  /// viewer, suspended members and anyone either party has blocked.
  ///
  /// An empty or blank [query] returns an empty list without a round trip. A
  /// directory that lists the whole membership the moment the field is focused
  /// has published a membership roll, and this app does not have that feature.
  Future<List<MemberCard>> searchMembers(String query, {int limit});

  /// People to follow: whoever most recently posted a public walk that the
  /// viewer is not already following.
  ///
  /// One rule, explainable in a sentence, because a suggestion in a prayer app
  /// should be answerable when somebody asks why they are being shown it.
  Future<List<MemberCard>> suggestedMembers({int limit});
}
