import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/feed_entry.dart';
import '../domain/feed_repository.dart';
import 'supabase_feed_repository.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => const SupabaseFeedRepository(),
);

/// Which half of the feed screen is showing.
///
/// Following is the default and stays the default. Explore is the door out of
/// an empty feed, not the front page — a member's own parish comes first, and a
/// stream of strangers should be something they walk towards.
enum FeedTab {
  following('Following'),
  explore('Explore');

  const FeedTab(this.label);
  final String label;
}

class FeedTabController extends Notifier<FeedTab> {
  @override
  FeedTab build() => FeedTab.following;

  void set(FeedTab tab) => state = tab;
}

final feedTabProvider = NotifierProvider<FeedTabController, FeedTab>(
  FeedTabController.new,
);

/// The signed-in person's feed. Empty while signed out, and empty — not
/// broken — for someone who follows nobody and hasn't walked yet.
final feedProvider = FutureProvider<List<FeedEntry>>((ref) {
  final viewerId = ref.watch(currentAuthUserIdProvider);
  if (viewerId == null) return Future.value(const []);
  return ref.watch(feedRepositoryProvider).feedFor(viewerId);
});

/// Public walks from people the member does not follow.
///
/// Empty here means something specific and worth saying on screen: nobody has
/// yet chosen to make a walk public. It is not an error, and it is not the same
/// emptiness as a feed with nobody followed.
final exploreFeedProvider = FutureProvider<List<FeedEntry>>((ref) {
  final viewerId = ref.watch(currentAuthUserIdProvider);
  if (viewerId == null) return Future.value(const []);
  return ref.watch(feedRepositoryProvider).exploreFor(viewerId);
});
