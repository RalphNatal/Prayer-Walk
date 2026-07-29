import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/scripture_delivery_repository.dart';
import '../domain/scripture_history.dart';

/// `scripture_deliveries`, from the app's side.
///
/// The whole point of this class is that it is allowed to fail. A walk selects
/// from the on-device record and never waits on this; what it buys is that a
/// member who signs in on a second phone does not start the library again. So
/// every read answers with an empty history rather than throwing, and every
/// write logs and returns. The one exception is [clear], which is a deliberate
/// action with a confirmation behind it and must not claim success it did not
/// have.
class SupabaseScriptureDeliveryRepository implements ScriptureDeliveryRepository {
  const SupabaseScriptureDeliveryRepository();

  static const _tag = 'PW-SCRIP';
  static const _table = 'scripture_deliveries';

  /// Long enough for a slow connection on the way home, short enough that a
  /// sync attempted as a walk finishes gives up rather than hanging about.
  static const _timeout = Duration(seconds: 8);

  /// Enough to rebuild any history this app can produce — the library is capped
  /// at a few hundred prompts by the NLT ceiling, and a member would have to
  /// walk daily for years to log this many arrivals. A bound rather than a
  /// policy, so a runaway sync cannot pull an unbounded result onto a phone.
  static const _fetchLimit = 5000;

  @override
  Future<ScriptureHistory> history() async {
    try {
      // Inside the try, not before it: reaching `supabase` at all throws when
      // the client has not been initialised, which is the ordinary state in a
      // test and a real one during startup. That is the same "no history to be
      // had" as being signed out, and must not surface as an error.
      final me = supabase.auth.currentUser?.id;
      if (me == null) return const ScriptureHistory.empty();

      final rows = await supabase
          .from(_table)
          .select('prompt_id, delivered_at')
          // Redundant beside the owner-only select policy, and kept anyway: the
          // filter is what makes the (user_id, prompt_id, delivered_at) index
          // usable, and a query that states its own scope is easier to read
          // than one relying on a policy elsewhere to narrow it.
          .eq('user_id', me)
          .order('delivered_at', ascending: false)
          .limit(_fetchLimit)
          .timeout(_timeout);

      return _fold(rows);
    } catch (error) {
      // Signed out, offline, or the table not yet migrated. All three mean the
      // same thing to the caller: carry on with what is on the device.
      AppLogger.info(
        _tag,
        'delivery history not synced (${error.runtimeType}) — using local',
      );
      return const ScriptureHistory.empty();
    }
  }

  /// Event rows → the per-prompt summary the device keeps.
  ///
  /// The server holds one row per arrival; the device holds one entry per
  /// passage. Folding here rather than in the store means the summary is built
  /// the same way from either side, so a reconcile cannot end up comparing two
  /// different notions of "when did I last see this".
  static ScriptureHistory _fold(List<dynamic> rows) {
    final entries = <String, ScriptureSeen>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final promptId = (row['prompt_id'] as String?)?.trim() ?? '';
      final at = DateTime.tryParse((row['delivered_at'] ?? '').toString());
      if (promptId.isEmpty || at == null) continue;

      final local = at.toLocal();
      final existing = entries[promptId];
      entries[promptId] = existing == null
          ? ScriptureSeen(firstSeenAt: local, lastSeenAt: local)
          : existing.seenAgainAt(local);
    }
    return ScriptureHistory(entries);
  }

  @override
  Future<void> record(Iterable<ScriptureDeliveryRecord> deliveries) async {
    if (deliveries.isEmpty) return;

    try {
      // Inside the try for the reason [history] gives — and it matters more
      // here, because this runs as a walk ends. An uninitialised client must
      // not throw out of a fire-and-forget call at the moment somebody is
      // saving their walk.
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;

      await supabase
          .from(_table)
          .insert([
            for (final delivery in deliveries)
              {
                'user_id': me,
                'prompt_id': delivery.promptId,
                // Sent rather than left to the column default. The default is
                // `now()`, which is when the row reached the server — and a
                // phone that was in a valley syncs hours later. The moment the
                // passage was actually read is the one the cooldown and the
                // least-recently-seen ordering need.
                'delivered_at': delivery.deliveredAt.toUtc().toIso8601String(),
                if (delivery.activityId != null)
                  'activity_id': delivery.activityId,
              },
          ])
          .timeout(_timeout);
    } catch (error) {
      // The device already has the record; this is the mirror falling behind.
      // It catches up on the next sync, and until then the only thing lost is
      // continuity onto a second phone.
      AppLogger.info(
        _tag,
        'could not mirror ${deliveries.length} deliveries '
        '(${error.runtimeType}) — kept locally',
      );
    }
  }

  @override
  Future<void> clear() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;
    await supabase.from(_table).delete().eq('user_id', me).timeout(_timeout);
  }
}
