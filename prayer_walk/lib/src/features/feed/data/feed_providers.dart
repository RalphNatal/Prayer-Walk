import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/feed_entry.dart';
import '../domain/feed_repository.dart';
import 'supabase_feed_repository.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => const SupabaseFeedRepository(),
);

/// The signed-in person's feed. Empty while signed out, and empty — not
/// broken — for someone who follows nobody and hasn't walked yet.
final feedProvider = FutureProvider<List<FeedEntry>>((ref) {
  final viewerId = ref.watch(currentAuthUserIdProvider);
  if (viewerId == null) return Future.value(const []);
  return ref.watch(feedRepositoryProvider).feedFor(viewerId);
});
