/// What a member has already been given, and when.
///
/// The memory the old recorder did not have. Delivery used to leave no trace
/// beyond the waypoint on the activity, so every walk reshuffled the whole
/// library from scratch — which is why a passage came back on the second walk
/// almost every time. This is the record that makes "unseen first, then least
/// recently seen" answerable.
///
/// **Aggregated per prompt rather than one entry per delivery.** The server
/// keeps the event log (`scripture_deliveries`, one row per arrival); the
/// device keeps this summary. That is the right split: a walk needs to know
/// *whether* and *how recently*, never *how many times over what history*, and
/// a summary stays small enough to read synchronously at the start of a walk
/// even after years of walking.
class ScriptureSeen {
  const ScriptureSeen({
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.count = 1,
  });

  /// The first time this passage reached this member, on any device.
  ///
  /// Kept because reconciliation prefers it: a row can reach
  /// `scripture_deliveries` long after the walk it belongs to — a phone that
  /// was offline in a valley syncs when it gets home — so the earliest
  /// timestamp for a passage is the one closest to when it was actually read.
  /// A later one is a sync artefact.
  final DateTime firstSeenAt;

  /// The most recent time it reached them. This is what the cooldown and the
  /// least-recently-seen ordering both read: "have I had this lately" is a
  /// question about the last time, not the first.
  final DateTime lastSeenAt;

  /// How many times in total. Not used for ranking — it is here so a future
  /// "you have read this seven times" is possible without a schema change, and
  /// so merging two devices does not silently lose the fact that both saw it.
  final int count;

  ScriptureSeen mergedWith(ScriptureSeen other) => ScriptureSeen(
    firstSeenAt: firstSeenAt.isBefore(other.firstSeenAt)
        ? firstSeenAt
        : other.firstSeenAt,
    lastSeenAt: lastSeenAt.isAfter(other.lastSeenAt)
        ? lastSeenAt
        : other.lastSeenAt,
    // The larger rather than the sum: the two devices' logs overlap wherever
    // one has already synced to the other, so adding them would double-count.
    count: count > other.count ? count : other.count,
  );

  ScriptureSeen seenAgainAt(DateTime at) => ScriptureSeen(
    firstSeenAt: at.isBefore(firstSeenAt) ? at : firstSeenAt,
    lastSeenAt: at.isAfter(lastSeenAt) ? at : lastSeenAt,
    count: count + 1,
  );

  Map<String, dynamic> toJson() => {
    'first': firstSeenAt.toUtc().toIso8601String(),
    'last': lastSeenAt.toUtc().toIso8601String(),
    'n': count,
  };

  /// Null for anything unreadable. A corrupt entry is one passage that looks
  /// unseen, which costs a little freshness and nothing else — never a throw on
  /// the way into a walk.
  static ScriptureSeen? fromJson(Object? value) {
    if (value is! Map) return null;
    final first = DateTime.tryParse((value['first'] ?? '').toString());
    final last = DateTime.tryParse((value['last'] ?? '').toString());
    if (first == null && last == null) return null;
    final resolvedLast = (last ?? first)!.toLocal();
    final resolvedFirst = (first ?? last)!.toLocal();
    return ScriptureSeen(
      firstSeenAt: resolvedFirst,
      lastSeenAt: resolvedLast,
      count: (value['n'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Every passage this member has received, keyed by prompt id.
///
/// Immutable, and cheap to copy: selection reads it once at the top of a walk
/// and again whenever the queue is rebuilt, and recording a delivery makes a
/// new one rather than mutating the one a walk is already holding.
class ScriptureHistory {
  const ScriptureHistory(this.entries);

  const ScriptureHistory.empty() : entries = const {};

  final Map<String, ScriptureSeen> entries;

  bool get isEmpty => entries.isEmpty;
  int get seenCount => entries.length;

  bool hasSeen(String promptId) => entries.containsKey(promptId);

  DateTime? lastSeen(String promptId) => entries[promptId]?.lastSeenAt;

  /// This member's history with one more arrival folded in.
  ScriptureHistory recording(String promptId, DateTime at) {
    final existing = entries[promptId];
    return ScriptureHistory({
      ...entries,
      promptId: existing == null
          ? ScriptureSeen(firstSeenAt: at, lastSeenAt: at)
          : existing.seenAgainAt(at),
    });
  }

  /// Union of two histories — the cross-device reconcile.
  ///
  /// Neither side wins outright: a passage in either has been seen, its first
  /// sighting is the earlier of the two, and its last sighting is the later.
  /// That is what stops a member who picks up a second phone from starting the
  /// library again, and equally stops the second phone's empty history from
  /// erasing what the first one knows.
  ScriptureHistory unionWith(ScriptureHistory other) {
    if (other.isEmpty) return this;
    if (isEmpty) return other;
    final merged = <String, ScriptureSeen>{...entries};
    for (final entry in other.entries.entries) {
      final mine = merged[entry.key];
      merged[entry.key] = mine == null
          ? entry.value
          : mine.mergedWith(entry.value);
    }
    return ScriptureHistory(merged);
  }

  /// The most recently seen [limit] passages, and nothing older.
  ///
  /// A bound rather than a policy: at any pool size this project will reach,
  /// one entry per prompt means the cap is never hit. It exists so that a
  /// library that grows unexpectedly — or a corrupt write that invents ids —
  /// cannot let the stored record grow without end on somebody's phone.
  ScriptureHistory capped(int limit) {
    if (entries.length <= limit) return this;
    final ordered = entries.entries.toList()
      ..sort((a, b) => b.value.lastSeenAt.compareTo(a.value.lastSeenAt));
    return ScriptureHistory({
      for (final entry in ordered.take(limit)) entry.key: entry.value,
    });
  }

  Map<String, dynamic> toJson() => {
    for (final entry in entries.entries) entry.key: entry.value.toJson(),
  };

  static ScriptureHistory fromJson(Object? value) {
    if (value is! Map) return const ScriptureHistory.empty();
    final entries = <String, ScriptureSeen>{};
    for (final entry in value.entries) {
      final seen = ScriptureSeen.fromJson(entry.value);
      if (seen != null) entries[entry.key.toString()] = seen;
    }
    return ScriptureHistory(entries);
  }
}
