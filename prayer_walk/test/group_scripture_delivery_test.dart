import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_prompt_store.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_row_mapper.dart';
import 'package:prayer_walk/src/features/scripture/data/supabase_scripture_repository.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_history.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_library.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_selector.dart';
import 'package:prayer_walk/src/features/scripture/presentation/scripture_reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The pool a walk draws from once church groups exist: the global library
/// plus the walker's own churches, as one pool.
///
/// What `walk_scripture_library()` returns from the server is asserted in
/// `supabase/tests/database/group_scripture.test.sql`. This is the device's
/// half — that the two sources travel together through the cache, the
/// edition filter and the freshness ranking without one crowding out, or
/// slipping past, the other.

const _stAnne = '6a1d4c66-3333-4333-8333-333333333333';

ScripturePrompt _global(String id, {String translation = 'WEBBE'}) =>
    ScripturePrompt(
      id: id,
      reference: 'Psalm $id',
      body: 'Global verse $id.',
      translation: translation,
      category: DevotionalCategory.stillness,
    );

ScripturePrompt _fromGroup(
  String id, {
  String translation = 'WEBBE',
  ScripturePromptKind kind = ScripturePromptKind.scripture,
}) => ScripturePrompt(
  id: id,
  reference: 'Isaiah $id',
  body: 'St Anne verse $id.',
  translation: translation,
  kind: kind,
  category: DevotionalCategory.stillness,
  groupId: _stAnne,
  groupName: 'St Anne',
);

/// A repository whose network read fails, as it does in a test with no
/// Supabase — so what is delivered comes from the cache written here, exactly
/// as it would on a walk with no signal.
Future<ScriptureLibrary> _deliveredFromCache(
  List<ScripturePrompt> cached, {
  required String translation,
}) async {
  SharedPreferences.setMockInitialValues({});
  const store = ScripturePromptStore();
  await store.writeCache(cached);
  return SupabaseScriptureRepository(store, translation).publishedLibrary();
}

void main() {
  group('a group verse is a group verse wherever it travels', () {
    test('the walk RPC row maps its group', () {
      final prompt = scripturePromptFromRow({
        'id': 'p1',
        'reference': 'Isaiah 40:31',
        'body': 'Those who wait for Yahweh will renew their strength.',
        'translation': 'WEBBE',
        'kind': 'scripture',
        'category': 'stillness',
        'group_id': _stAnne,
        'church_group': {'id': _stAnne, 'name': 'St Anne'},
        'contributor': null,
      });
      expect(prompt.isFromGroup, isTrue);
      expect(prompt.groupName, 'St Anne');
      expect(prompt.hasContributor, isFalse);
    });

    test('a global row has no group', () {
      final prompt = scripturePromptFromRow({
        'id': 'p2',
        'reference': 'Psalm 121:1',
        'body': 'I will lift up my eyes.',
        'group_id': null,
        'church_group': null,
      });
      expect(prompt.isFromGroup, isFalse);
      expect(prompt.groupName, '');
    });

    test('the offline cache keeps the group and its name', () {
      final back = scripturePromptFromRow(
        scripturePromptToRow(_fromGroup('g1')),
      );
      expect(back.groupId, _stAnne);
      expect(back.groupName, 'St Anne');
    });

    test('and a global prompt is cached without group keys at all', () {
      expect(
        scripturePromptToRow(_global('1')).containsKey('group_id'),
        isFalse,
      );
    });
  });

  group('the combined pool and the edition filter', () {
    test('a WEBBE build gets the library and the church together', () async {
      final library = await _deliveredFromCache([
        _global('1'),
        _global('2'),
        _fromGroup('g1'),
      ], translation: 'WEBBE');

      expect(library.source, ScriptureLibrarySource.cache);
      expect(library.prompts.map((p) => p.id), containsAll(['1', '2', 'g1']));
    });

    test("an NLT build keeps its church's public-domain verse", () async {
      // The global library has both editions; the build asks for the NLT. The
      // global WEBBE row is filtered out as before — but the group's verse is
      // the group's choice, has no NLT equivalent, and is delivered anyway.
      final library = await _deliveredFromCache([
        _global('1'),
        _global('1-nlt', translation: 'NLT'),
        _fromGroup('g1'),
      ], translation: 'NLT');

      final ids = library.prompts.map((p) => p.id).toList();
      expect(ids, contains('1-nlt'));
      expect(ids, contains('g1'));
      expect(ids, isNot(contains('1')));
      expect(library.fellBack, isFalse);
      // The group's verse still carries its own edition, not the build's mark.
      final groupVerse = library.prompts.firstWhere((p) => p.id == 'g1');
      expect(groupVerse.attributedBody, isNot(contains('(NLT)')));
    });

    test(
      "a church's WEBBE verse does not stop an NLT build falling back",
      () async {
        // No NLT rows at all. Before groups, this fell back to the whole
        // library. A group's WEBBE verse must not be mistaken for "the library
        // has something in the configured edition" and leave the walk with
        // one church's verse and nothing else.
        final library = await _deliveredFromCache([
          _global('1'),
          _global('2'),
          _fromGroup('g1'),
        ], translation: 'NLT');

        expect(library.fellBack, isTrue);
        expect(library.prompts.map((p) => p.id), containsAll(['1', '2', 'g1']));
      },
    );

    test('a group prayer is delivered under every edition', () async {
      for (final translation in ['WEBBE', 'NLT']) {
        final library = await _deliveredFromCache([
          _global('1', translation: translation),
          _fromGroup('gp', translation: '', kind: ScripturePromptKind.prayer),
        ], translation: translation);
        expect(library.prompts.map((p) => p.id), contains('gp'));
      }
    });
  });

  group('the cooldown spans both sources', () {
    final now = DateTime(2026, 10, 16, 7);

    test('a church verse from yesterday rests like a library verse does', () {
      final pool = [
        _global('1'),
        _global('2'),
        _fromGroup('g1'),
        _fromGroup('g2'),
      ];
      final history = const ScriptureHistory.empty()
          .recording('1', now.subtract(const Duration(days: 1)))
          .recording('g1', now.subtract(const Duration(days: 1)));

      final ranked = rankScripturePrompts(
        library: pool,
        history: history,
        now: now,
        random: math.Random(7),
      ).map((p) => p.id).toList();

      // Both unseen prompts — one from each source — come before both resting
      // ones, whichever source they came from.
      expect(ranked.sublist(0, 2), unorderedEquals(['2', 'g2']));
      expect(ranked.sublist(2), unorderedEquals(['1', 'g1']));
    });

    test('an unseen library verse outranks a church verse from yesterday', () {
      final ranked = rankScripturePrompts(
        library: [_fromGroup('g1'), _global('1')],
        history: const ScriptureHistory.empty().recording(
          'g1',
          now.subtract(const Duration(days: 2)),
        ),
        now: now,
        random: math.Random(1),
      );
      expect(ranked.first.id, '1');
    });

    test('and the other way round', () {
      final ranked = rankScripturePrompts(
        library: [_global('1'), _fromGroup('g1')],
        history: const ScriptureHistory.empty().recording(
          '1',
          now.subtract(const Duration(days: 2)),
        ),
        now: now,
        random: math.Random(1),
      );
      expect(ranked.first.id, 'g1');
    });

    test('nothing is dropped: the ranking is a permutation of both', () {
      final pool = [
        for (var i = 0; i < 6; i++) _global('$i'),
        for (var i = 0; i < 6; i++) _fromGroup('g$i'),
      ];
      final ranked = rankScripturePrompts(library: pool, now: now);
      expect(ranked.map((p) => p.id).toSet(), pool.map((p) => p.id).toSet());
      expect(ranked, hasLength(pool.length));
    });
  });

  group('no connection, no cache', () {
    test(
      'a member of a church still gets verses — the bundled floor',
      () async {
        SharedPreferences.setMockInitialValues({});
        final library = await const SupabaseScriptureRepository(
          ScripturePromptStore(),
          'WEBBE',
        ).publishedLibrary();

        // Group scripture cannot be bundled; it is never silence instead.
        expect(library.source, ScriptureLibrarySource.bundled);
        expect(library.prompts, isNotEmpty);
        expect(library.prompts.every((p) => !p.isFromGroup), isTrue);
      },
    );
  });

  group('the credit says where a verse came from', () {
    Future<void> pump(WidgetTester tester, ScripturePrompt prompt) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: ScriptureBody(prompt: prompt)),
          ),
        );

    testWidgets("a church's verse is credited to the church", (tester) async {
      await pump(tester, _fromGroup('g1'));
      expect(find.text('Shared by St Anne'), findsOneWidget);
      expect(find.text('WEBBE'), findsOneWidget);
    });

    testWidgets('a library verse claims no church', (tester) async {
      await pump(tester, _global('1'));
      expect(find.textContaining('Shared by'), findsNothing);
    });

    testWidgets('the provenance stays when the edition credit is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ScriptureBody(
              prompt: _fromGroup('g1'),
              showTranslation: false,
            ),
          ),
        ),
      );
      expect(find.text('Shared by St Anne'), findsOneWidget);
      expect(find.text('WEBBE'), findsNothing);
    });

    test('the bundled floor is still WEBBE', () {
      expect(BibleTranslation.fallback, BibleTranslation.webbe);
    });
  });
}
