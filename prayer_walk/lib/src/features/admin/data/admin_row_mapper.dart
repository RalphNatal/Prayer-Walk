import '../../profile/data/profile_row_mapper.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/admin_models.dart';

/// Rows ⇄ the console's models, in one place.
///
/// The profile rows the admin functions return are mapped by
/// `userProfileFromRow` like every other profile in the app — the members
/// table, the dashboard's recent signups and the feed byline all resolve to the
/// same person, because they all go through the same mapper.

/// The `announcements` columns every read selects.
const announcementColumns =
    'id, title, body, audience, sent_at, sent_by_name, recipient_count';

/// One `admin_metrics()` row.
AdminMetrics adminMetricsFromRow(Map<String, dynamic> row) {
  return AdminMetrics(
    totalMembers: _int(row['total_members']),
    activeThisWeek: _int(row['active_this_week']),
    activitiesLogged: _int(row['activities_logged']),
    devotionalsPublished: _int(row['devotionals_published']),
    activitySeries: [
      for (final day in _list(row['activity_series']))
        DailyCount(
          date: DateTime.tryParse('${day['date']}') ?? DateTime.now(),
          count: _int(day['count']),
        ),
    ],
    recentSignups: [
      for (final person in _list(row['recent_signups']))
        userProfileFromRow(person),
    ],
  );
}

/// One `admin_reports()` / `admin_resolve_report()` row.
///
/// A null excerpt means the walk or comment is gone. The copy here is what the
/// queue shows, and it is stated plainly rather than dressed up as content.
ModerationReport moderationReportFromRow(Map<String, dynamic> row) {
  final excerpt = (row['target_excerpt'] as String?)?.trim();
  final removed = excerpt == null || excerpt.isEmpty;

  return ModerationReport(
    id: (row['id'] ?? '').toString(),
    targetType: _targetType(row['target_type'] as String?),
    targetId: (row['target_id'] ?? '').toString(),
    targetExcerpt: removed ? 'This content has been removed.' : excerpt,
    targetAuthorName:
        (row['target_author_name'] as String?)?.trim() ?? 'Unknown',
    reportedByName: (row['reported_by_name'] as String?)?.trim() ?? 'A member',
    reason: (row['reason'] as String?)?.trim() ?? '',
    createdAt: _time(row['created_at']) ?? DateTime.now(),
    status: reportStatusFrom(row['status'] as String?),
    targetRemoved: removed,
  );
}

Announcement announcementFromRow(Map<String, dynamic> row) {
  return Announcement(
    id: (row['id'] ?? '').toString(),
    title: (row['title'] as String?)?.trim() ?? '',
    body: (row['body'] as String?)?.trim() ?? '',
    audience: audienceFrom(row['audience'] as String?),
    sentAt: _time(row['sent_at']) ?? DateTime.now(),
    sentByName: (row['sent_by_name'] as String?)?.trim() ?? 'An admin',
    recipientCount: _int(row['recipient_count']),
  );
}

/// Enums are stored by their Dart value name, the convention every other table
/// in this schema follows. An unrecognised value takes the safest reading
/// rather than throwing: a queue that will not load is worse than one row
/// showing as pending.
ReportStatus reportStatusFrom(String? value) => ReportStatus.values.firstWhere(
  (s) => s.name == value,
  orElse: () => ReportStatus.pending,
);

AnnouncementAudience audienceFrom(String? value) =>
    AnnouncementAudience.values.firstWhere(
      (a) => a.name == value,
      orElse: () => AnnouncementAudience.everyone,
    );

/// The `admin_members()` rows carry the profile columns plus a count, so the
/// members table gets both in one round trip.
List<UserProfile> membersFromRows(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map) userProfileFromRow(Map<String, dynamic>.from(row)),
];

ReportTargetType _targetType(String? value) =>
    ReportTargetType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ReportTargetType.activity,
    );

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

/// A jsonb array column arrives as a `List`; anything else is treated as empty
/// rather than crashing the dashboard.
List<Map<String, dynamic>> _list(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is Map) Map<String, dynamic>.from(item),
];
