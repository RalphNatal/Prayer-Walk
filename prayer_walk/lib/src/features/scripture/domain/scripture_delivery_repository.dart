import 'scripture_history.dart';

/// The server's copy of what a member has been given.
///
/// Deliberately its own seam rather than three more methods on
/// [ScriptureRepository]. The library is shared content that everyone reads and
/// admins curate; this is one person's devotional record, owner-only in RLS and
/// never joined to anything public. Keeping them apart means a future change to
/// the library's access cannot widen this by accident, and means the walk-time
/// stub in the tests does not have to know this exists.
///
/// **Nothing here is on the critical path of a walk.** Every method is
/// best-effort: selection reads the on-device record, and these calls carry it
/// between phones afterwards. Implementations swallow their failures.
abstract interface class ScriptureDeliveryRepository {
  /// Everything the server holds for the signed-in member, folded into the
  /// same shape the device keeps. Empty when signed out, offline, or on any
  /// failure — an empty remote history is indistinguishable from an unreachable
  /// one here, and both mean "carry on with what is local".
  Future<ScriptureHistory> history();

  /// Pushes deliveries the server has not seen. Best-effort and idempotent by
  /// (member, prompt, moment), so a retry after a failed sync does not multiply
  /// the record.
  Future<void> record(Iterable<ScriptureDeliveryRecord> deliveries);

  /// Clears the member's whole record, for "start the library fresh".
  ///
  /// Unlike the others this one reports failure, because it is a deliberate
  /// action taken from a settings screen with a confirmation behind it. Telling
  /// somebody their history was cleared when it was not is worse than telling
  /// them it could not be.
  Future<void> clear();
}

/// One arrival, on its way to the server.
class ScriptureDeliveryRecord {
  const ScriptureDeliveryRecord({
    required this.promptId,
    required this.deliveredAt,
    this.activityId,
  });

  final String promptId;
  final DateTime deliveredAt;

  /// The walk it arrived on, when there is one. Null for a delivery whose walk
  /// was discarded before it saved — the passage was still read.
  final String? activityId;
}
