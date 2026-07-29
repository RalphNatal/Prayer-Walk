import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/devotionals/data/devotional_providers.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/devotionals/presentation/devotional_reader_screen.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_prompt_store.dart';
import 'package:prayer_walk/src/features/scripture/data/supabase_scripture_repository.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/presentation/scripture_reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stub_repositories.dart';

/// Attribution, asserted rather than inspected.
///
/// A licensed translation's per-quotation mark is a condition of use, and the
/// way it gets lost is not malice — it is a sixth display path added a year
/// from now by someone who never read the licence. So the guarantees here are
/// deliberately structural: the mark comes from the text, not from the screen;
/// no preference can switch it off; and the last test in this file fails the
/// build if a new screen reaches around the shared widget to draw a verse
/// itself.
///
/// **No NLT text appears anywhere in this file.** Every licensed row below
/// carries obviously synthetic placeholder prose. What is being tested is the
/// machinery around the words, which is exactly what can be tested without
/// them.

/// A stand-in for licensed text. Says what it is, so it cannot be mistaken for
/// a quotation if it ever escapes into a fixture somewhere else.
const _placeholder = 'Placeholder passage — not licensed text.';

ScripturePrompt _prompt({
  required String translation,
  String reference = 'Psalm 121:1-2',
  String body = _placeholder,
}) => ScripturePrompt(
  id: 'p_test',
  reference: reference,
  body: body,
  translation: translation,
  category: DevotionalCategory.scriptureWalk,
);

Devotional _devotional({required String translation}) => Devotional(
  id: 'd_test',
  title: 'A devotional',
  summary: 'One line.',
  body: 'A paragraph.',
  scriptureRef: 'Psalm 121:1-2',
  scriptureText: _placeholder,
  translation: translation,
  category: DevotionalCategory.scriptureWalk,
  authorName: 'Prayer Walk',
  updatedAt: DateTime(2026, 7, 28),
  isPublished: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the terms of a translation', () {
    test('an edition that requires a mark gets one', () {
      expect(BibleTranslation.nlt.attributed('A verse.'), 'A verse. (NLT)');
    });

    test('a public-domain edition gets none', () {
      expect(BibleTranslation.webbe.attributed('A verse.'), 'A verse.');
      expect(BibleTranslation.webbe.quotationMark, isEmpty);
    });

    test('a prayer, quoting nobody, gets none', () {
      expect(BibleTranslation.none.attributed('A prayer.'), 'A prayer.');
      expect(BibleTranslation.none.isQuotation, isFalse);
    });

    test('marking is idempotent', () {
      // A waypoint note is stored already marked and may pass through the
      // formatter again on its way to a screen. Once is once.
      final once = BibleTranslation.nlt.attributed('A verse.');
      expect(BibleTranslation.nlt.attributed(once), once);
    });

    test('empty text is left alone', () {
      expect(BibleTranslation.nlt.attributed(''), '');
      expect(BibleTranslation.nlt.attributed('   '), '   ');
    });

    test('an unknown edition fails closed — marked, and named as unknown', () {
      final unknown = BibleTranslation.of('ESV');
      expect(unknown.isKnown, isFalse);
      expect(unknown.requiresQuotationMark, isTrue);
      expect(unknown.requiresAttribution, isTrue);
      expect(unknown.attributed('A verse.'), 'A verse. (ESV)');
    });

    test('lookup is case- and space-insensitive, and WEB reads as WEBBE', () {
      expect(BibleTranslation.of(' nlt '), BibleTranslation.nlt);
      // The column default written by the original migration.
      expect(BibleTranslation.of('WEB'), BibleTranslation.webbe);
      expect(BibleTranslation.of(null), BibleTranslation.none);
      expect(BibleTranslation.of(''), BibleTranslation.none);
    });

    test("Tyndale's credit line is carried verbatim", () {
      // Character for character. Reflowing, paraphrasing or abbreviating it is
      // the thing this test exists to catch — the licence names this wording.
      expect(
        BibleTranslation.nlt.creditLine,
        'Scripture quotations are taken from the Holy Bible, New Living '
        'Translation, copyright © 1996, 2004, 2015 by Tyndale House '
        'Foundation. Used by permission of Tyndale House Publishers, Carol '
        'Stream, Illinois 60188. All rights reserved.',
      );
    });
  });

  group('a prompt carries its own attribution', () {
    test('the body a screen may draw is the marked one', () {
      expect(_prompt(translation: 'NLT').attributedBody, endsWith('(NLT)'));
      expect(_prompt(translation: 'WEBBE').attributedBody, _placeholder);
    });

    test('the spoken form is marked too', () {
      // The voice and the screen reader are display paths like any other.
      expect(_prompt(translation: 'NLT').spoken, endsWith('(NLT)'));
    });

    test('a devotional passage is marked on the same seam', () {
      expect(
        _devotional(translation: 'NLT').attributedScriptureText,
        endsWith('(NLT)'),
      );
      expect(
        _devotional(translation: 'WEBBE').attributedScriptureText,
        _placeholder,
      );
    });
  });

  group('no display path can drop the mark', () {
    testWidgets('the arrival card and the reading show it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptureBody(prompt: _prompt(translation: 'NLT')),
          ),
        ),
      );
      expect(find.textContaining('(NLT)'), findsOneWidget);
    });

    testWidgets('turning the credit off does not turn the mark off', (
      tester,
    ) async {
      // `showTranslation` is the walker's preference about a courtesy credit.
      // It has no authority over a licence condition, and this is the assertion
      // that keeps it that way.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptureBody(
              prompt: _prompt(translation: 'NLT'),
              showTranslation: false,
            ),
          ),
        ),
      );
      expect(find.textContaining('(NLT)'), findsOneWidget);
    });

    testWidgets('truncating to a card-sized excerpt keeps it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ScriptureBody(
                prompt: _prompt(translation: 'NLT'),
                maxLines: 2,
              ),
            ),
          ),
        ),
      );
      // The mark is part of the string, so it survives into whatever the
      // ellipsis leaves — the widget is not free to render text without it.
      final rendered = tester.widget<Text>(
        find.textContaining('(NLT)', skipOffstage: false),
      );
      expect(rendered.data, endsWith('(NLT)'));
    });

    testWidgets('a public-domain verse is not marked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptureBody(prompt: _prompt(translation: 'WEBBE')),
          ),
        ),
      );
      expect(find.textContaining('('), findsNothing);
      // The courtesy credit is still drawn: WEBBE owes nothing, but naming it
      // is the practice.
      expect(find.text('WEBBE'), findsOneWidget);
    });

    testWidgets('the devotional reader shows it', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            devotionalRepositoryProvider.overrideWithValue(
              StubDevotionalRepository([_devotional(translation: 'NLT')]),
            ),
          ],
          child: const MaterialApp(
            home: DevotionalReaderScreen(devotionalId: 'd_test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(NLT)'), findsOneWidget);
    });
  });

  group('the offline floor stays WEBBE', () {
    test('a bundled verse is credited WEBBE even on an NLT build', () async {
      SharedPreferences.setMockInitialValues({});

      // Configured for the NLT, with no network and no cache: what a walk gets
      // is the set shipped in the binary, which is public domain.
      const repository = SupabaseScriptureRepository(
        ScripturePromptStore(),
        'NLT',
      );
      final prompts = await repository.publishedPrompts();

      expect(prompts, isNotEmpty);
      expect(
        prompts.map((p) => p.translation).toSet(),
        everyElement(anyOf('WEBBE', '')),
        reason: 'nothing licensed is bundled in the binary',
      );
      expect(
        prompts.every((p) => !p.attributedBody.contains('(NLT)')),
        isTrue,
        reason: 'a fallback verse must not inherit the configured mark',
      );
    });
  });

  group('the configured translation decides what is delivered', () {
    /// A mixed library, as the table looks once both editions are seeded.
    List<ScripturePrompt> mixed() => [
      _prompt(translation: 'WEBBE', reference: 'Psalm 46:10'),
      _prompt(translation: 'NLT', reference: 'Psalm 46:10'),
      const ScripturePrompt(
        id: 'p_prayer',
        reference: 'The Jesus Prayer',
        body: 'Lord Jesus Christ, Son of God, have mercy on me, a sinner.',
        kind: ScripturePromptKind.prayer,
        category: DevotionalCategory.lament,
      ),
    ];

    Future<List<ScripturePrompt>> deliveredUnder(String translation) async {
      SharedPreferences.setMockInitialValues({});
      const store = ScripturePromptStore();
      await store.writeCache(mixed());
      // Supabase is not initialized in a test, so the fetch fails exactly as it
      // does on a walk with no signal and the cache answers.
      return SupabaseScriptureRepository(store, translation).publishedPrompts();
    }

    test('switching editions needs no content rewrite', () async {
      final webbe = await deliveredUnder('WEBBE');
      expect(webbe.map((p) => p.translation), ['WEBBE', '']);

      final nlt = await deliveredUnder('NLT');
      expect(nlt.map((p) => p.translation), ['NLT', '']);
    });

    test('a prayer is delivered under every edition', () async {
      // It quotes nobody, so it belongs to all of them rather than to none.
      for (final translation in ['WEBBE', 'NLT']) {
        final delivered = await deliveredUnder(translation);
        expect(
          delivered.where((p) => p.kind == ScripturePromptKind.prayer),
          hasLength(1),
        );
      }
    });

    test('an edition with no rows yet still gets a walk', () async {
      SharedPreferences.setMockInitialValues({});
      const store = ScripturePromptStore();
      await store.writeCache([
        _prompt(translation: 'WEBBE', reference: 'Psalm 46:10'),
      ]);

      // Configured for an edition nothing has been seeded in. Delivering
      // nothing would be the worse failure, so the whole library comes
      // through — still carrying its own, correct, attribution.
      final delivered = await SupabaseScriptureRepository(
        store,
        'NLT',
      ).publishedPrompts();
      expect(delivered, hasLength(1));
      expect(delivered.single.translation, 'WEBBE');
      expect(delivered.single.attributedBody, isNot(contains('(NLT)')));
    });
  });

  group('counting against the licensed ceiling', () {
    test('a range counts as the verses it spans', () {
      expect(approximateVerseCount('Psalm 46:10'), 1);
      expect(approximateVerseCount('Psalm 121:1-2'), 2);
      expect(approximateVerseCount('1 Thessalonians 5:16-18'), 3);
      expect(approximateVerseCount(''), 0);
      // Undercounts rather than over: the shapes it cannot expand read as one,
      // which is why the number shown to an admin is called approximate.
      expect(approximateVerseCount('Psalm 1:1,3'), 1);
    });

    test("Tyndale's ceiling is the number the app curates against", () {
      expect(kNltVerseCeiling, 500);
    });
  });

  group('the structural guarantee', () {
    test('no screen draws a quotation without going through the seam', () {
      // The other tests in this file prove the shared widget marks a verse.
      // This one proves nothing bypasses it — which is the promise that has to
      // survive the next screen somebody adds. It reads the source, because
      // that is where the mistake would be made.
      const seam = <String>{
        // Where the mark is defined and applied.
        'lib/src/features/scripture/domain/bible_translation.dart',
        'lib/src/features/scripture/domain/scripture_prompt.dart',
        'lib/src/features/scripture/presentation/scripture_quotation.dart',
        'lib/src/features/devotionals/domain/devotional.dart',
        // Row ⇄ model, and the writes behind them. These move the column, they
        // do not draw it.
        'lib/src/features/scripture/data/scripture_row_mapper.dart',
        'lib/src/features/scripture/data/supabase_scripture_repository.dart',
        'lib/src/features/scripture/domain/scripture_repository.dart',
        'lib/src/features/devotionals/data/devotional_row_mapper.dart',
        'lib/src/features/devotionals/data/supabase_devotional_repository.dart',
        // The admin editors, which put the raw text in a field to be edited.
        // An editor is entering the quotation, not quoting it.
        'lib/src/features/admin/presentation/admin_content_form_screen.dart',
        // The one write that marks text on its way *out* of the prompt: a
        // scripture waypoint's note is persisted, so it is attributed at the
        // moment the edition is still known. See RecordingController.
        'lib/src/features/activity/data/recording_controller.dart',
      };

      // Reaching for the raw text of a quotation. `.body` alone would catch
      // every devotional's prose, which is not a quotation and not the concern.
      final raw = RegExp(r'(prompt\.body|\.scriptureText)\b');

      // The one sanctioned way a screen may hold raw text: handing it to
      // ScriptureQuotation, which is what puts the mark on. Anything else —
      // a bare Text, a string interpolation, a Semantics label — is the bug.
      final handedToTheWidget = RegExp(
        r'^\s*text:\s*\w+\.(body|scriptureText),\s*$',
      );
      // Matched on the widget rather than on an import path: the file next to
      // it reaches it with a bare relative import.
      const widget = 'ScriptureQuotation(';

      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (seam.contains(path)) continue;
        final source = entity.readAsStringSync();
        final drawsThroughTheWidget = source.contains(widget);
        for (final line in source.split('\n')) {
          if (!raw.hasMatch(line)) continue;
          if (drawsThroughTheWidget && handedToTheWidget.hasMatch(line)) {
            continue;
          }
          offenders.add('$path — ${line.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A quotation reached a screen without its translation.\n'
            'Draw it with ScriptureQuotation, or read the marked text from '
            'ScripturePrompt.attributedBody / '
            'Devotional.attributedScriptureText.\n'
            'If this file genuinely handles the column rather than displaying '
            'it, add it to the seam set above and say why.\n'
            'Found: ${offenders.join(', ')}',
      );
    });
  });
}
