import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/domain/user_profile.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';
import 'supabase_admin_repository.dart';

/// The console's providers, over the real tables.
///
/// Nothing here is admin-gated in Dart on purpose. The router keeps a member
/// out of these screens, and the database refuses every one of these calls to a
/// non-admin — a provider that also checked would be a third place for the
/// answer to live, and the only one that could be wrong.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => const SupabaseAdminRepository(),
);

final adminMetricsProvider = FutureProvider<AdminMetrics>(
  (ref) => ref.watch(adminRepositoryProvider).metrics(),
);

/// Search + filter state for the members table.
class MemberQueryController extends Notifier<MemberQuery> {
  @override
  MemberQuery build() => const MemberQuery();

  void search(String value) => state = state.copyWith(search: value);

  void setRole(UserRole? role) =>
      state = state.copyWith(role: role, clearRole: role == null);

  void setStatus(MemberStatus? status) =>
      state = state.copyWith(status: status, clearStatus: status == null);

  void clear() => state = const MemberQuery();
}

final memberQueryControllerProvider =
    NotifierProvider<MemberQueryController, MemberQuery>(
      MemberQueryController.new,
    );

final adminMembersProvider = FutureProvider<List<UserProfile>>(
  (ref) => ref
      .watch(adminRepositoryProvider)
      .members(ref.watch(memberQueryControllerProvider)),
);

final adminMemberProvider = FutureProvider.family<UserProfile, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).memberById(id),
);

final memberActivityCountProvider = FutureProvider.family<int, String>(
  (ref, id) => ref.watch(adminRepositoryProvider).activityCountFor(id),
);

/// Which slice of the moderation queue is showing.
class ModerationFilter extends Notifier<ReportStatus?> {
  @override
  ReportStatus? build() => ReportStatus.pending;

  void set(ReportStatus? status) => state = status;
}

final moderationFilterProvider =
    NotifierProvider<ModerationFilter, ReportStatus?>(ModerationFilter.new);

final moderationQueueProvider = FutureProvider<List<ModerationReport>>(
  (ref) => ref
      .watch(adminRepositoryProvider)
      .reports(status: ref.watch(moderationFilterProvider)),
);

/// Drives the badge on the Moderation destination.
final pendingReportCountProvider = FutureProvider<int>((ref) async {
  final pending = await ref
      .watch(adminRepositoryProvider)
      .reports(status: ReportStatus.pending);
  return pending.length;
});

final announcementsProvider = FutureProvider<List<Announcement>>(
  (ref) => ref.watch(adminRepositoryProvider).announcements(),
);

final audienceSizeProvider = FutureProvider.family<int, AnnouncementAudience>(
  (ref, audience) => ref.watch(adminRepositoryProvider).audienceSize(audience),
);
