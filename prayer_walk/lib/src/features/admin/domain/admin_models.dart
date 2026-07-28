import '../../profile/domain/user_profile.dart';

/// One bar in the "activities over time" chart.
class DailyCount {
  const DailyCount({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class AdminMetrics {
  const AdminMetrics({
    required this.totalMembers,
    required this.activeThisWeek,
    required this.activitiesLogged,
    required this.devotionalsPublished,
    required this.activitySeries,
    required this.recentSignups,
  });

  final int totalMembers;
  final int activeThisWeek;
  final int activitiesLogged;
  final int devotionalsPublished;
  final List<DailyCount> activitySeries;
  final List<UserProfile> recentSignups;
}

enum ReportTargetType {
  activity('Activity'),
  comment('Comment');

  const ReportTargetType(this.label);
  final String label;
}

enum ReportStatus {
  pending('Pending'),
  resolved('Resolved'),
  dismissed('Dismissed');

  const ReportStatus(this.label);
  final String label;
}

class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.targetExcerpt,
    required this.targetAuthorName,
    required this.reportedByName,
    required this.reason,
    required this.createdAt,
    required this.status,
    this.targetRemoved = false,
  });

  final String id;
  final ReportTargetType targetType;
  final String targetId;
  final String targetExcerpt;
  final String targetAuthorName;
  final String reportedByName;
  final String reason;
  final DateTime createdAt;
  final ReportStatus status;

  /// The walk or comment this is about no longer exists — deleted by its
  /// author, or removed by another admin, after the report was filed.
  ///
  /// `target_id` points at either table and carries no foreign key, so this is
  /// an ordinary state rather than an error: the report still happened and
  /// still has to be closed by somebody. The queue renders it as "content
  /// removed" rather than dropping the row or failing the read.
  final bool targetRemoved;

  ModerationReport copyWith({ReportStatus? status}) => ModerationReport(
    id: id,
    targetType: targetType,
    targetId: targetId,
    targetExcerpt: targetExcerpt,
    targetAuthorName: targetAuthorName,
    reportedByName: reportedByName,
    reason: reason,
    createdAt: createdAt,
    status: status ?? this.status,
    targetRemoved: targetRemoved,
  );
}

enum AnnouncementAudience {
  everyone('Everyone'),
  activeMembers('Active members'),
  admins('Admins only');

  const AnnouncementAudience(this.label);
  final String label;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.sentAt,
    required this.sentByName,
    required this.recipientCount,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final DateTime sentAt;
  final String sentByName;
  final int recipientCount;
}

/// Filter state for the members table.
class MemberQuery {
  const MemberQuery({this.search = '', this.role, this.status});

  final String search;
  final UserRole? role;
  final MemberStatus? status;

  MemberQuery copyWith({
    String? search,
    UserRole? role,
    MemberStatus? status,
    bool clearRole = false,
    bool clearStatus = false,
  }) {
    return MemberQuery(
      search: search ?? this.search,
      role: clearRole ? null : (role ?? this.role),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}
