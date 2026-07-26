import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/feed_entry.dart';
import '../domain/feed_repository.dart';

class MockFeedRepository implements FeedRepository {
  MockFeedRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<List<FeedEntry>> feedFor(String viewerId) {
    return _backend.readList(() {
      final followed = _backend.follows
          .where((f) => f.followerId == viewerId)
          .map((f) => f.followeeId)
          .toSet()
        ..add(viewerId);

      final rows =
          _backend.activities.where((a) => followed.contains(a.userId)).toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      return rows
          .map(
            (a) => FeedEntry(
              activity: _backend.hydrate(a, viewerId),
              author: _backend.userById(a.userId),
            ),
          )
          .toList(growable: false);
    });
  }
}

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => MockFeedRepository(ref.watch(mockBackendProvider)),
);

final feedProvider = FutureProvider<List<FeedEntry>>((ref) {
  final viewerId = ref.watch(currentUserIdProvider);
  if (viewerId == null) return Future.value(const []);
  return ref.watch(feedRepositoryProvider).feedFor(viewerId);
});
