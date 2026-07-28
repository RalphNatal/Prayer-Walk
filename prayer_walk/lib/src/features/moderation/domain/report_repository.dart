import '../../admin/domain/admin_models.dart' show ReportTargetType;

/// The member's half of moderation.
///
/// One method, because a member does exactly one thing here: says that
/// something is wrong. Everything after that — the queue, the excerpt, the
/// decision — belongs to `AdminRepository` and is not readable from this side.
abstract interface class ReportRepository {
  /// Files a report as the signed-in member.
  ///
  /// Filing the same report twice is not an error the person should ever see:
  /// the table has one row per member per target, and a second attempt is
  /// treated as the report already being on the record.
  Future<void> report({
    required ReportTargetType targetType,
    required String targetId,
    required String reason,
  });
}
