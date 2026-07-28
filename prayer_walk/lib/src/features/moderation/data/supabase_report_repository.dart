import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../admin/domain/admin_models.dart' show ReportTargetType;
import '../domain/report_repository.dart';

/// Writes into `moderation_reports` as the signed-in member.
///
/// `reported_by` comes from the session, never from a parameter: the insert
/// policy requires `auth.uid() = reported_by`, so an attempt to file a report
/// in someone else's name is refused by the database, not by this class.
class SupabaseReportRepository implements ReportRepository {
  const SupabaseReportRepository();

  @override
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required String reason,
  }) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) {
      throw const AppException('Sign in again, then try reporting this.');
    }

    try {
      await supabase.from('moderation_reports').insert({
        'target_type': targetType.name,
        'target_id': targetId,
        'reason': reason.trim(),
        'reported_by': me,
      });
    } on PostgrestException catch (error) {
      // 23505 = the unique constraint on (target_type, target_id, reported_by).
      // Reporting the same thing twice is not a failure — it means what the
      // person wanted is already true.
      if (error.code == '23505') return;
      rethrow;
    }
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => const SupabaseReportRepository(),
);
