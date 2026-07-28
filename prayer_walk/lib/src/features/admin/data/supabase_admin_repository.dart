import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../profile/data/supabase_profile_repository.dart';
import '../../profile/domain/profile_repository.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';
import 'admin_row_mapper.dart';

/// The real console, against real rows.
///
/// Every read here is one round trip, because each one goes through a SQL
/// function that has already done the joining and counting — `admin_metrics`,
/// `admin_members`, `admin_reports`, `admin_resolve_report`. The dashboard used
/// to be four queries; the members table used to be a count per row.
///
/// None of those functions is `security definer`. RLS applies inside them
/// exactly as it does out here, and each one additionally refuses a caller who
/// is not an admin. Hiding the console behind the router's redirect is a
/// convenience; the database is the boundary.
class SupabaseAdminRepository implements AdminRepository {
  const SupabaseAdminRepository([
    this._profiles = const SupabaseProfileRepository(),
  ]);

  /// Member detail shows the same person the member app shows — same row, same
  /// mapper, same lifetime stats. There is no separate "admin view" of someone.
  final ProfileRepository _profiles;

  @override
  Future<AdminMetrics> metrics() async {
    final rows = await supabase.rpc('admin_metrics') as List<dynamic>;
    if (rows.isEmpty) throw AppException.notFound;
    return adminMetricsFromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  @override
  Future<List<UserProfile>> members(MemberQuery query) async {
    final rows =
        await supabase.rpc(
              'admin_members',
              params: {
                // Empty means "no filter" server-side, so the screen's
                // controller state goes through unmodified.
                'search': query.search.trim(),
                'role_filter': query.role?.name,
                'status_filter': query.status?.name,
                'limit_count': 500,
              },
            )
            as List<dynamic>;
    return membersFromRows(rows);
  }

  @override
  Future<UserProfile> memberById(String id) => _profiles.profileById(id);

  @override
  Future<int> activityCountFor(String userId) async {
    // `member_stats` already derives this, and it is the same number the
    // member's own profile shows — reading it from anywhere else would be a
    // second way to count the same walks.
    final rows =
        await supabase.rpc('member_stats', params: {'target': userId})
            as List<dynamic>;
    if (rows.isEmpty) return 0;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return (row['activity_count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<UserProfile> setRole(String userId, UserRole role) =>
      _write(userId, {'role': role.name}, "That role change didn't stick.");

  @override
  Future<UserProfile> setStatus(String userId, MemberStatus status) =>
      _write(userId, {'status': status.name}, "That change didn't stick.");

  /// The one write path onto another member's `profiles` row.
  ///
  /// Two failures matter here and neither may pass silently:
  ///
  ///  * 42501 — a rule said no. That is the role trigger refusing a self-role
  ///    change, or an admin reaching for a column the console has no business
  ///    in. The database wrote the sentence; it is shown as-is rather than
  ///    replaced with a generic "permission denied", because it names the
  ///    actual rule.
  ///  * zero rows — the update was allowed to run and matched nothing, which is
  ///    what a missing admin policy looked like before this phase. It reads as
  ///    success at every layer above unless it is caught right here.
  Future<UserProfile> _write(
    String userId,
    Map<String, dynamic> patch,
    String fallback,
  ) async {
    final List<dynamic> rows;
    try {
      rows = await supabase
          .from('profiles')
          .update(patch)
          .eq('id', userId)
          .select('id');
    } on PostgrestException catch (error) {
      if (error.code == '42501') throw AppException(error.message);
      rethrow;
    }

    if (rows.isEmpty) {
      throw AppException('$fallback You may not have permission to do that.');
    }
    return memberById(userId);
  }

  @override
  Future<List<ModerationReport>> reports({ReportStatus? status}) async {
    final rows =
        await supabase.rpc(
              'admin_reports',
              params: {'status_filter': status?.name},
            )
            as List<dynamic>;
    return [
      for (final row in rows)
        if (row is Map) moderationReportFromRow(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Future<ModerationReport> resolveReport(
    String id,
    ReportStatus outcome,
  ) async {
    final rows =
        await supabase.rpc(
              'admin_resolve_report',
              params: {'report_id': id, 'outcome': outcome.name},
            )
            as List<dynamic>;
    if (rows.isEmpty) throw AppException.notFound;
    return moderationReportFromRow(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<List<Announcement>> announcements() async {
    final rows = await supabase
        .from('announcements')
        .select(announcementColumns)
        .order('sent_at', ascending: false);
    return [
      for (final row in rows) announcementFromRow(row),
    ];
  }

  @override
  Future<Announcement> sendAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required String sentByName,
  }) async {
    // Counted immediately before the insert, so the number stored on the row is
    // the number of people it actually went to — not a live count that quietly
    // grows as members join.
    final recipients = await audienceSize(audience);

    final row = await supabase
        .from('announcements')
        .insert({
          'title': title.trim(),
          'body': body.trim(),
          'audience': audience.name,
          'sent_by': supabase.auth.currentUser?.id,
          'sent_by_name': sentByName,
          'recipient_count': recipients,
        })
        .select(announcementColumns)
        .single();
    return announcementFromRow(row);
  }

  @override
  Future<int> audienceSize(AnnouncementAudience audience) async {
    final count = await supabase.rpc(
      'audience_size',
      params: {'audience': audience.name},
    );
    return (count as num?)?.toInt() ?? 0;
  }
}
