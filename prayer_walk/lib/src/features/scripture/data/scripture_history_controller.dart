import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/scripture_delivery_repository.dart';
import '../domain/scripture_history.dart';
import 'scripture_prompt_store.dart';
import 'supabase_scripture_delivery_repository.dart';

/// What this member has already been given, held where a walk can reach it.
///
/// A plain [Notifier] rather than an [AsyncNotifier], for the reason
/// `ScriptureSettingsController` gives about preferences: every reader wants an
/// answer synchronously. The recorder asks "what have they seen" at the moment
/// the library lands, and an empty history is a correct answer for the handful
/// of frames before the stored one arrives — it means one walk selects as
/// though the member were new, which costs a little freshness and never costs
/// the walk. Making the recorder await a history read would put a disk read on
/// the path between pressing Start and the first verse.
///
/// **Local is the truth during a walk.** [record] updates state synchronously,
/// persists in the background, and queues the arrival for the server. The
/// server copy exists so a second phone does not start the library again; it is
/// never consulted to decide what to deliver.
class ScriptureHistoryController extends Notifier<ScriptureHistory> {
  static const _tag = 'PW-SCRIP';

  ScripturePromptStore get _store => ref.read(scripturePromptStoreProvider);
  ScriptureDeliveryRepository get _remote =>
      ref.read(scriptureDeliveryRepositoryProvider);

  /// Arrivals the server has not been told about yet.
  ///
  /// Flushed when a walk ends rather than as each verse lands: a walk crossing
  /// an interval is the worst moment to start a network request, and a walk
  /// produces a dozen of them. Anything still here when the app dies is
  /// recovered by [reconcile], which diffs rather than replays — so nothing is
  /// lost by keeping this in memory.
  final List<ScriptureDeliveryRecord> _pending = [];

  bool _disposed = false;

  @override
  ScriptureHistory build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_hydrate());
    return const ScriptureHistory.empty();
  }

  Future<void> _hydrate() async {
    final stored = await _store.readHistory();
    if (_disposed || stored.isEmpty) return;
    // Union rather than assignment: a verse may have been delivered in the few
    // frames between build() and this read, and overwriting would forget it.
    state = state.unionWith(stored);
  }

  // ------------------------------------------------------------ delivering ---

  /// Notes that [promptId] reached this member at [at].
  ///
  /// Synchronous where it matters and best-effort everywhere else. Called from
  /// the recorder immediately after a verse is handed to the walker, so by the
  /// time anything here can fail the passage has already been read — which is
  /// why nothing in this method is awaited and nothing in it can throw.
  void record(String promptId, {DateTime? at, String? activityId}) {
    if (promptId.isEmpty) return;
    final moment = at ?? DateTime.now();

    state = state.recording(promptId, moment);
    _pending.add(
      ScriptureDeliveryRecord(
        promptId: promptId,
        deliveredAt: moment,
        activityId: activityId,
      ),
    );
    unawaited(_store.writeHistory(state));
  }

  /// Pushes what a walk delivered to the server. Called when a walk ends.
  ///
  /// Never awaited by the recorder, and never reports failure: a walk that
  /// finished successfully must not show an error because a mirror was
  /// unreachable. Whatever fails here is recovered by the next [reconcile].
  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final batch = List<ScriptureDeliveryRecord>.of(_pending);
    _pending.clear();
    await _remote.record(batch);
  }

  // ----------------------------------------------------------- cross-device ---

  /// Merges the server's record with this device's, in both directions.
  ///
  /// Run on sign-in, which is the moment a second phone would otherwise start
  /// the library from zero. The union is [ScriptureHistory.unionWith]: a
  /// passage either side has seen counts as seen, its first sighting is the
  /// earlier of the two and its last is the later. Neither side can erase the
  /// other — an empty history on a fresh install does not wipe what the server
  /// knows, and a server that has never been reached does not wipe the phone.
  ///
  /// Then the difference goes back the other way, so the phone that has been
  /// walking offline for a fortnight teaches the server what it missed.
  Future<void> reconcile() async {
    try {
      final remote = await _remote.history();
      if (_disposed) return;

      final local = state;
      final merged = local.unionWith(remote);
      if (_disposed) return;
      state = merged;
      await _store.writeHistory(merged);

      await _remote.record(_unmirrored(local, remote));
      _pending.clear();
    } catch (error) {
      // Every failure here has the same answer — keep walking with what is on
      // the device. Reported at info because a reconcile that cannot reach the
      // server is the ordinary offline case, not a fault.
      AppLogger.info(
        _tag,
        'delivery history not reconciled (${error.runtimeType})',
      );
    }
  }

  /// What this device knows and the server does not.
  ///
  /// A summary per passage rather than a replay of every arrival — one row for
  /// the most recent sighting the server has not got. That is all the ordering
  /// and the cooldown read, and it keeps a fortnight of offline walking to a
  /// few hundred rows rather than a few thousand.
  static List<ScriptureDeliveryRecord> _unmirrored(
    ScriptureHistory local,
    ScriptureHistory remote,
  ) {
    final missing = <ScriptureDeliveryRecord>[];
    for (final entry in local.entries.entries) {
      final theirs = remote.entries[entry.key];
      if (theirs != null && !entry.value.lastSeenAt.isAfter(theirs.lastSeenAt)) {
        continue;
      }
      missing.add(
        ScriptureDeliveryRecord(
          promptId: entry.key,
          deliveredAt: entry.value.lastSeenAt,
        ),
      );
    }
    return missing;
  }

  // ---------------------------------------------------------------- resetting ---

  /// "Start the library fresh."
  ///
  /// Clears the server first and the device second. That order matters: if the
  /// server call fails this throws with the device record intact, so the member
  /// is told it did not work rather than left with a phone that has forgotten
  /// everything and a server that will hand it all back at the next reconcile.
  Future<void> reset() async {
    await _remote.clear();
    _pending.clear();
    state = const ScriptureHistory.empty();
    await _store.clearHistory();
  }
}

final scripturePromptStoreProvider = Provider<ScripturePromptStore>(
  (ref) => const ScripturePromptStore(),
);

final scriptureDeliveryRepositoryProvider =
    Provider<ScriptureDeliveryRepository>(
      (ref) => const SupabaseScriptureDeliveryRepository(),
    );

/// The one delivery record the app reads. Not auto-disposed: the recorder holds
/// it for the length of a walk, and settings reads the same instance so the
/// progress line and the walk cannot disagree.
final scriptureHistoryProvider =
    NotifierProvider<ScriptureHistoryController, ScriptureHistory>(
      ScriptureHistoryController.new,
    );

/// Pulls the server's record down whenever somebody signs in.
///
/// This is the whole of "a member on a new phone should not restart from zero".
/// A fresh install has an empty local history, so without this its first walk
/// would treat a library the member worked through last year as entirely
/// unseen. Watching the auth phase rather than firing once at startup is what
/// makes it work for the second account on a shared phone as well as the second
/// phone for one account.
///
/// Deliberately a side-effecting provider with no value: nothing reads a result
/// from it, and nothing waits on it. It is watched once, high up, and the
/// reconcile it triggers is best-effort — a sign-in on a train with no signal
/// simply carries on with the local record and syncs later.
final scriptureHistorySyncProvider = Provider<void>((ref) {
  if (ref.watch(authPhaseProvider) != AuthPhase.signedIn) return;
  unawaited(ref.read(scriptureHistoryProvider.notifier).reconcile());
});
