import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

class MockAdminRepository implements AdminRepository {
  MockAdminRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<AdminMetrics> metrics() {
    return _backend.read(() {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final activeIds = _backend.activities
          .where((a) => a.startedAt.isAfter(weekAgo))
          .map((a) => a.userId)
          .toSet();

      final series = List.generate(14, (i) {
        final day = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: 13 - i));
        final count = _backend.activities
            .where(
              (a) =>
                  a.startedAt.year == day.year &&
                  a.startedAt.month == day.month &&
                  a.startedAt.day == day.day,
            )
            .length;
        // The fixtures cluster on a few days; nudge the rest so the chart
        // placeholder reads as a trend rather than a single spike.
        return DailyCount(date: day, count: count + (i % 4) + (i ~/ 5));
      });

      final signups = _backend.users.toList()
        ..sort((a, b) => b.joinedAt.compareTo(a.joinedAt));

      return AdminMetrics(
        totalMembers: _backend.users.length,
        activeThisWeek: activeIds.length,
        activitiesLogged: _backend.activities.length,
        devotionalsPublished: _backend.devotionals
            .where((d) => d.isPublished)
            .length,
        activitySeries: series,
        recentSignups: signups.take(5).toList(growable: false),
      );
    });
  }

  @override
  Future<List<UserProfile>> members(MemberQuery query) {
    return _backend.readList(() {
      final search = query.search.trim().toLowerCase();
      final rows =
          _backend.users
              .where(
                (u) =>
                    search.isEmpty ||
                    u.displayName.toLowerCase().contains(search) ||
                    u.handle.toLowerCase().contains(search) ||
                    u.parish.toLowerCase().contains(search),
              )
              .where((u) => query.role == null || u.role == query.role)
              .where((u) => query.status == null || u.status == query.status)
              .toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
      return rows;
    });
  }

  @override
  Future<UserProfile> memberById(String id) =>
      _backend.read(() => _backend.userById(id));

  @override
  Future<int> activityCountFor(String userId) => _backend.read(
    () => _backend.activities.where((a) => a.userId == userId).length,
  );

  @override
  Future<UserProfile> setRole(String userId, UserRole role) {
    return _backend.write(() {
      final updated = _backend.userById(userId).copyWith(role: role);
      _backend.replaceUser(updated);
      return updated;
    });
  }

  @override
  Future<UserProfile> setStatus(String userId, MemberStatus status) {
    return _backend.write(() {
      final updated = _backend.userById(userId).copyWith(status: status);
      _backend.replaceUser(updated);
      return updated;
    });
  }

  @override
  Future<List<ModerationReport>> reports({ReportStatus? status}) {
    return _backend.readList(
      () =>
          _backend.reports.where((r) => status == null || r.status == status).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  @override
  Future<ModerationReport> resolveReport(String id, ReportStatus outcome) {
    return _backend.write(() {
      final index = _backend.reports.indexWhere((r) => r.id == id);
      final updated = _backend.reports[index].copyWith(status: outcome);
      _backend.reports[index] = updated;
      return updated;
    });
  }

  @override
  Future<List<Announcement>> announcements() {
    return _backend.readList(
      () => _backend.announcements.toList()
        ..sort((a, b) => b.sentAt.compareTo(a.sentAt)),
    );
  }

  @override
  Future<Announcement> sendAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required String sentByName,
  }) {
    return _backend.write(() {
      final sent = Announcement(
        id: _backend.nextId('an'),
        title: title.trim(),
        body: body.trim(),
        audience: audience,
        sentAt: DateTime.now(),
        sentByName: sentByName,
        recipientCount: _audienceSize(audience),
      );
      _backend.announcements.add(sent);
      return sent;
    });
  }

  @override
  Future<int> audienceSize(AnnouncementAudience audience) =>
      _backend.read(() => _audienceSize(audience));

  int _audienceSize(AnnouncementAudience audience) => switch (audience) {
    AnnouncementAudience.everyone => _backend.users.length,
    AnnouncementAudience.activeMembers => _backend.users
        .where((u) => u.status == MemberStatus.active)
        .length,
    AnnouncementAudience.admins => _backend.users
        .where((u) => u.role == UserRole.admin)
        .length,
  };
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => MockAdminRepository(ref.watch(mockBackendProvider)),
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

final audienceSizeProvider =
    FutureProvider.family<int, AnnouncementAudience>(
      (ref, audience) =>
          ref.watch(adminRepositoryProvider).audienceSize(audience),
    );
