import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/discovery_repository.dart';
import '../domain/member_card.dart';
import 'supabase_discovery_repository.dart';

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => SupabaseDiscoveryRepository(ref.watch(currentAuthUserIdProvider)),
);

/// What is currently typed in the Discover field.
///
/// A notifier rather than local widget state so the result provider can watch
/// it — and so that arriving on Discover from an empty feed with a term already
/// in mind is a one-line change rather than a plumbing exercise.
class MemberSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final memberSearchQueryProvider =
    NotifierProvider<MemberSearchQuery, String>(MemberSearchQuery.new);

/// Search results for the current term.
///
/// Auto-disposed: a search is a moment, not a standing subscription, and
/// holding the last query's results while somebody walks is nothing but memory.
final memberSearchProvider = FutureProvider.autoDispose<List<MemberCard>>((
  ref,
) {
  final query = ref.watch(memberSearchQueryProvider);
  return ref.watch(discoveryRepositoryProvider).searchMembers(query);
});

/// People to follow. Watched by the empty feed and by Discover.
///
/// Not auto-disposed: the empty feed and Discover both show it, and a member
/// bouncing between the two should not re-fetch the same eight people.
final suggestedMembersProvider = FutureProvider<List<MemberCard>>(
  (ref) => ref.watch(discoveryRepositoryProvider).suggestedMembers(),
);
