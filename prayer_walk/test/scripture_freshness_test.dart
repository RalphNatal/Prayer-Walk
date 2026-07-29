import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_prompt_store.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_history.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Freshness, from the selection side.
///
/// The complaint this answers is that passages repeated across walks. The cause
/// was not the shuffle: it was that the recorder reshuffled the whole library
/// at the start of every walk with no memory of the last one, so each walk was
/// an independent draw and two draws of a dozen from forty-seven collide almost
/// every time.
///
/// [rankScripturePrompts] is pure, so the promises can be asserted directly
/// rather than inferred from a simulated walk — the walk-shaped version of the
/// same guarantee lives in `scripture_delivery_test.dart`, which drives the
/// recorder through ten consecutive outings.

ScripturePrompt prompt(
  String id, {
  String reference = 'Psalm 1:1',
  DevotionalCategory category = DevotionalCategory.stillness,
  ScripturePromptKind kind = ScripturePromptKind.scripture,
}) => ScripturePrompt(
  id: id,
  reference: reference,
  body: 'Body of $id.',
  translation: 'WEBBE',
  category: category,
  kind: kind,
);

List<ScripturePrompt> library(int count) => [
  for (var i = 0; i < count; i++) prompt('sp_$i', reference: 'Psalm ${i + 1}:1'),
];

final _now = DateTime(2026, 7, 29, 9);

ScriptureHistory seenAt(Map<String, DateTime> entries) => ScriptureHistory({
  for (final entry in entries.entries)
    entry.key: ScriptureSeen(
      firstSeenAt: entry.value,
      lastSeenAt: entry.value,
    ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unseen first', () {
    test('a passage never delivered outranks every passage that has been', () {
      final ranked = rankScripturePrompts(
        library: library(6),
        // Everything except sp_4 was seen a long time ago, so recency cannot be
        // what puts sp_4 first — only never having been seen can.
        history: seenAt({
          for (var i = 0; i < 6; i++)
            if (i != 4) 'sp_$i': _now.subtract(const Duration(days: 400)),
        }),
        now: _now,
      );

      expect(ranked.first.id, 'sp_4');
      expect(ranked, hasLength(6), reason: 'ranking is a permutation');
    });

    test('unseen passages come in some order, not the library order', () {
      // Twenty unseen passages, ranked twice. Two identical orderings would
      // mean everybody walks the library the same way from the same start.
      final first = rankScripturePrompts(library: library(20), now: _now);
      final second = rankScripturePrompts(library: library(20), now: _now);

      expect(
        first.map((p) => p.id).toList(),
        isNot(second.map((p) => p.id).toList()),
      );
      expect(first.map((p) => p.id).toSet(), hasLength(20));
    });

    test('seen passages are ordered oldest sighting first', () {
      final ranked = rankScripturePrompts(
        library: library(4),
        history: seenAt({
          'sp_0': _now.subtract(const Duration(days: 100)),
          'sp_1': _now.subtract(const Duration(days: 400)),
          'sp_2': _now.subtract(const Duration(days: 200)),
          'sp_3': _now.subtract(const Duration(days: 300)),
        }),
        now: _now,
      );

      expect(ranked.map((p) => p.id), ['sp_1', 'sp_3', 'sp_2', 'sp_0']);
    });
  });

  group('the cooldown', () {
    test('a passage delivered yesterday is held behind everything else', () {
      final ranked = rankScripturePrompts(
        library: library(5),
        history: seenAt({'sp_2': _now.subtract(const Duration(days: 1))}),
        now: _now,
      );

      expect(
        ranked.last.id,
        'sp_2',
        reason: 'yesterday\'s passage waits until the library is exhausted',
      );
    });

    test('a passage older than the cooldown is available again', () {
      final ranked = rankScripturePrompts(
        library: library(5),
        history: seenAt({
          'sp_2': _now.subtract(const Duration(days: 31)),
          // The rest are resting, so if sp_2 were also resting it would not be
          // possible to tell the two states apart.
          'sp_0': _now.subtract(const Duration(days: 2)),
          'sp_1': _now.subtract(const Duration(days: 2)),
          'sp_3': _now.subtract(const Duration(days: 2)),
          'sp_4': _now.subtract(const Duration(days: 2)),
        }),
        now: _now,
      );

      expect(ranked.first.id, 'sp_2');
    });

    test('the configured length decides what is held back', () {
      // Asserted against a themed walk, because that is where the cooldown is
      // observable on its own. On an unthemed walk it agrees with the
      // least-recently-seen ordering by construction — the passages inside the
      // window are the most recent ones, so oldest-first would put them last
      // anyway. Here the theme preference would otherwise promote a passage
      // seen ten days ago above an unseen one, and the cooldown is what stops
      // it.
      List<String> rank(Duration cooldown) => rankScripturePrompts(
        library: [
          prompt('themed', category: DevotionalCategory.gratitude),
          prompt('other', category: DevotionalCategory.lament),
        ],
        history: seenAt({'themed': _now.subtract(const Duration(days: 10))}),
        preferred: DevotionalCategory.gratitude,
        cooldown: cooldown,
        now: _now,
      ).map((p) => p.id).toList();

      expect(rank(const Duration(days: 30)), ['other', 'themed']);
      expect(rank(const Duration(days: 5)), ['themed', 'other']);
    });

    test('an exhausted library still delivers, oldest first', () {
      // Every passage was seen inside the cooldown, so honouring it would mean
      // silence. It falls back rather than going quiet.
      final ranked = rankScripturePrompts(
        library: library(3),
        history: seenAt({
          'sp_0': _now.subtract(const Duration(days: 3)),
          'sp_1': _now.subtract(const Duration(days: 1)),
          'sp_2': _now.subtract(const Duration(days: 2)),
        }),
        now: _now,
      );

      expect(ranked, hasLength(3), reason: 'nothing is dropped');
      expect(ranked.map((p) => p.id), ['sp_0', 'sp_2', 'sp_1']);
    });
  });

  group('the chosen theme', () {
    test('is worked through before anything else', () {
      final ranked = rankScripturePrompts(
        library: [
          prompt('a', category: DevotionalCategory.lament),
          prompt('b', category: DevotionalCategory.gratitude),
          prompt('c', category: DevotionalCategory.lament),
          prompt('d', category: DevotionalCategory.gratitude),
          prompt('e', category: DevotionalCategory.lament),
        ],
        preferred: DevotionalCategory.gratitude,
        now: _now,
      );

      expect(
        ranked.take(2).map((p) => p.category),
        everyElement(DevotionalCategory.gratitude),
      );
      expect(ranked, hasLength(5), reason: 'and then keeps going');
    });

    test('does not override the cooldown', () {
      // The promise that yesterday's passage does not return today is the
      // stronger of the two: an unseen passage from outside the theme is a
      // better answer than an on-theme one from yesterday.
      final ranked = rankScripturePrompts(
        library: [
          prompt('themed', category: DevotionalCategory.gratitude),
          prompt('other', category: DevotionalCategory.lament),
        ],
        history: seenAt({'themed': _now.subtract(const Duration(days: 1))}),
        preferred: DevotionalCategory.gratitude,
        now: _now,
      );

      expect(ranked.first.id, 'other');
    });
  });

  group('variety', () {
    test('does not put two passages from the same book back to back', () {
      final ranked = rankScripturePrompts(
        library: [
          for (var i = 0; i < 4; i++)
            prompt('ps_$i', reference: 'Psalm ${i + 1}:1'),
          for (var i = 0; i < 4; i++)
            prompt('is_$i', reference: 'Isaiah ${i + 1}:1'),
        ],
        now: _now,
      );

      final books = [for (final p in ranked) scriptureBookOf(p)];
      for (var i = 1; i < books.length; i++) {
        expect(
          books[i],
          isNot(books[i - 1]),
          reason: 'four of each, alternating is always possible',
        );
      }
    });

    test('never starves delivery when everything is the same book', () {
      final ranked = rankScripturePrompts(
        library: [
          for (var i = 0; i < 8; i++)
            prompt('ps_$i', reference: 'Psalm ${i + 1}:1'),
        ],
        now: _now,
      );

      expect(
        ranked,
        hasLength(8),
        reason: 'variety is a preference, never a filter',
      );
      expect(ranked.map((p) => p.id).toSet(), hasLength(8));
    });

    test('reads a book off a reference, and buckets prayers together', () {
      expect(scriptureBookOf(prompt('a', reference: 'Psalm 121:1-2')), 'Psalm');
      expect(
        scriptureBookOf(prompt('b', reference: '1 Thessalonians 5:16-18')),
        '1 Thessalonians',
      );
      expect(
        scriptureBookOf(prompt('c', reference: 'Song of Songs 2:11-12')),
        'Song of Songs',
      );
      expect(
        scriptureBookOf(
          prompt(
            'd',
            reference: 'The Jesus Prayer',
            kind: ScripturePromptKind.prayer,
          ),
        ),
        '(prayer)',
      );
    });
  });

  group('history as a record', () {
    test('survives an app restart', () async {
      SharedPreferences.setMockInitialValues({});
      const store = ScripturePromptStore();

      await store.writeHistory(
        const ScriptureHistory.empty()
            .recording('sp_1', _now)
            .recording('sp_2', _now.subtract(const Duration(days: 5))),
      );

      // A second store instance is what a cold start looks like: nothing in
      // memory, everything read back from disk.
      const reopened = ScripturePromptStore();
      final restored = await reopened.readHistory();

      expect(restored.seenCount, 2);
      expect(restored.hasSeen('sp_1'), isTrue);
      expect(restored.lastSeen('sp_2'), _now.subtract(const Duration(days: 5)));
    });

    test('an unreadable record reads as nothing seen, and does not throw', () async {
      SharedPreferences.setMockInitialValues({
        'scripture.history.v1': 'this is not json',
      });

      final history = await const ScripturePromptStore().readHistory();

      expect(history.isEmpty, isTrue);
    });

    test('clearing it starts the library fresh', () async {
      SharedPreferences.setMockInitialValues({});
      const store = ScripturePromptStore();
      await store.writeHistory(
        const ScriptureHistory.empty().recording('sp_1', _now),
      );

      await store.clearHistory();

      expect((await store.readHistory()).isEmpty, isTrue);
    });

    test('is capped so it cannot grow without bound', () async {
      var history = const ScriptureHistory.empty();
      for (var i = 0; i < ScripturePromptStore.historyLimit + 50; i++) {
        history = history.recording(
          'sp_$i',
          // Ascending, so the ones dropped are the oldest.
          _now.subtract(Duration(minutes: 5000 - i)),
        );
      }

      final capped = history.capped(ScripturePromptStore.historyLimit);

      expect(capped.seenCount, ScripturePromptStore.historyLimit);
      expect(capped.hasSeen('sp_0'), isFalse, reason: 'oldest dropped');
      expect(capped.hasSeen('sp_1049'), isTrue, reason: 'newest kept');
    });

    test('a second delivery moves the last sighting but not the first', () {
      final history = const ScriptureHistory.empty()
          .recording('sp_1', _now.subtract(const Duration(days: 30)))
          .recording('sp_1', _now);

      expect(history.lastSeen('sp_1'), _now);
      expect(
        history.entries['sp_1']!.firstSeenAt,
        _now.subtract(const Duration(days: 30)),
      );
      expect(history.entries['sp_1']!.count, 2);
    });
  });

  group('a second device', () {
    test('does not restart the library from zero', () {
      // The old phone has walked half the library; the new one has walked
      // nothing. The union is what the new phone selects from.
      final onTheOldPhone = seenAt({
        'sp_0': _now.subtract(const Duration(days: 40)),
        'sp_1': _now.subtract(const Duration(days: 20)),
      });
      const onTheNewPhone = ScriptureHistory.empty();

      final merged = onTheNewPhone.unionWith(onTheOldPhone);

      expect(merged.seenCount, 2);
      final ranked = rankScripturePrompts(
        library: library(4),
        history: merged,
        now: _now,
      );
      expect(
        ranked.take(2).map((p) => p.id).toSet(),
        {'sp_2', 'sp_3'},
        reason: 'the unseen two come first on the new phone too',
      );
    });

    test('an empty local history cannot erase the server copy', () {
      final remote = seenAt({'sp_0': _now.subtract(const Duration(days: 3))});

      expect(const ScriptureHistory.empty().unionWith(remote).seenCount, 1);
      expect(remote.unionWith(const ScriptureHistory.empty()).seenCount, 1);
    });

    test('the union prefers the earliest first sighting and the latest last', () {
      final phoneA = ScriptureHistory({
        'sp_0': ScriptureSeen(
          firstSeenAt: _now.subtract(const Duration(days: 90)),
          lastSeenAt: _now.subtract(const Duration(days: 60)),
        ),
      });
      final phoneB = ScriptureHistory({
        'sp_0': ScriptureSeen(
          firstSeenAt: _now.subtract(const Duration(days: 70)),
          lastSeenAt: _now.subtract(const Duration(days: 2)),
        ),
      });

      final merged = phoneA.unionWith(phoneB);

      expect(
        merged.entries['sp_0']!.firstSeenAt,
        _now.subtract(const Duration(days: 90)),
        reason: 'the earliest sighting is the one closest to when it was read',
      );
      expect(
        merged.entries['sp_0']!.lastSeenAt,
        _now.subtract(const Duration(days: 2)),
        reason: 'and the cooldown must see the most recent one',
      );
    });
  });

  group('the shipped library', () {
    test('is large enough that a month of walking does not repeat', () async {
      SharedPreferences.setMockInitialValues({});
      final prompts = await const ScripturePromptStore().readBundled();

      // Twelve prompts is a 5 km walk at the default 400 m cadence. Thirty of
      // those is a month of daily walking.
      expect(
        prompts.length,
        greaterThanOrEqualTo(300),
        reason: 'the audit set the floor at 300; below it, history is not '
            'enough on its own',
      );
      expect(prompts.length, lessThanOrEqualTo(500));
    });

    test('carries no licensed translation', () {
      // Asserted rather than assumed. The bundled asset ships inside the
      // binary, which is a wider distribution question than a row on a server.
      expect(
        () async {
          SharedPreferences.setMockInitialValues({});
          final prompts = await const ScripturePromptStore().readBundled();
          for (final prompt in prompts) {
            expect(prompt.translation, anyOf('WEBBE', ''));
          }
        },
        returnsNormally,
      );
    });

    test('draws widely enough across the canon to not feel like one book', () async {
      SharedPreferences.setMockInitialValues({});
      final prompts = await const ScripturePromptStore().readBundled();

      final books = <String, int>{};
      for (final prompt in prompts) {
        final book = scriptureBookOf(prompt);
        if (book == '(prayer)') continue;
        books[book] = (books[book] ?? 0) + 1;
      }

      final scripture = prompts
          .where((p) => p.kind == ScripturePromptKind.scripture)
          .length;

      expect(
        books.length,
        greaterThanOrEqualTo(40),
        reason: 'the audit found 21 books; the expansion was meant to fix that',
      );
      expect(
        books['Psalm']! / scripture,
        lessThan(0.3),
        reason: 'Psalms was 41% of the old library, which read as repetitive '
            'even when technically fresh',
      );
    });

    test('gives every theme enough to carry a 5 km walk', () async {
      SharedPreferences.setMockInitialValues({});
      final prompts = await const ScripturePromptStore().readBundled();

      for (final category in DevotionalCategory.values) {
        final inTheme = prompts.where((p) => p.category == category).length;
        expect(
          inTheme,
          greaterThanOrEqualTo(12),
          reason: '${category.name} must last a 5 km walk at the default '
              'cadence without drifting off theme',
        );
      }
    });
  });
}
