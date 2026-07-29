/// The order a walk draws its verses in.
///
/// This replaces the shuffle that used to live in `RecordingController`. That
/// one reshuffled the whole library at the start of every walk with no memory
/// of what had been delivered before, which guaranteed no repeat *within* a
/// walk and made one near-certain *across* walks — two independent draws of a
/// dozen prompts from a pool of forty-seven collide 98% of the time. The walk
/// still draws from an ordered queue and still walks a cursor forward; what
/// changed is that the ordering can now see backwards.
///
/// **Pure on purpose.** Everything it needs — the library, the history, the
/// clock, the source of randomness — arrives as an argument, so the ranking can
/// be asserted directly instead of inferred from a simulated walk. It cannot
/// touch the network, cannot throw for anything a walk would notice, and cannot
/// be slow enough to matter: it is a couple of passes over a few hundred items.
library;

import 'dart:math' as math;

import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import 'scripture_history.dart';
import 'scripture_prompt.dart';

/// How far ahead the variety pass will look to avoid two passages from the same
/// book in a row.
///
/// Small deliberately. Variety is a preference sitting on top of a ranking that
/// has already been earned by recency, and a wide window would let cosmetic
/// spread overrule "this is the one you have not seen". Six is enough to break
/// up a run of Psalms and too short to reorder the queue in any way a member
/// would perceive as unfairness.
const int kVarietyWindow = 6;

/// One passage's place in the draw, before the queue is flattened.
class _Ranked {
  _Ranked(this.prompt, this.book);
  final ScripturePrompt prompt;
  final String book;
}

/// The book a reference belongs to — `Psalm 121:1-2` → `Psalm`.
///
/// Used only by the variety pass, so a reference this does not recognise costs
/// a little spread and nothing else. Prayers share one bucket rather than each
/// getting their own: two prayers back to back is the thing being avoided, and
/// they have names rather than books.
String scriptureBookOf(ScripturePrompt prompt) {
  if (prompt.kind == ScripturePromptKind.prayer) return '(prayer)';
  final match = RegExp(
    r'^(.*?)\s+\d+\s*[:.]\s*[\d,\-–\s]+$',
  ).firstMatch(prompt.reference.trim());
  final book = match?.group(1)?.trim();
  return (book == null || book.isEmpty) ? prompt.reference.trim() : book;
}

/// The whole library, ordered for this member and this walk.
///
/// The ranking, in the order the rules apply:
///
///  1. **The chosen theme first.** Unchanged from before: a themed walk works
///     through everything in its theme before it reaches anything else, so an
///     ordinary walk only ever sees its theme and a long one keeps receiving
///     verses instead of going silent at the end of a short collection.
///  2. **Never delivered to this member**, shuffled among themselves — so two
///     members who start on the same day do not walk the library in the same
///     order, and so a first walk is not deterministic.
///  3. **Then least recently delivered**, oldest first.
///  4. **Anything received inside [cooldown] is held back entirely** and
///     appended after everything else. It is reached only once the pool is
///     genuinely exhausted, which is what keeps "delivered yesterday" from
///     reappearing today while leaving a very long walk with something to say.
///
///     On an unthemed walk this agrees with rule 3 by construction — the
///     passages inside the window are the most recent ones, so oldest-first
///     would put them last regardless. It earns its place on a *themed* walk,
///     where rule 1 would otherwise promote an on-theme passage from yesterday
///     above an unseen one from outside the theme, and as the explicit
///     statement of a promise that must survive future changes to the ranking.
///  5. **Then a soft variety pass** — see [_spread].
///
/// The result is a permutation of [library]: every prompt appears exactly once,
/// which is what preserves the within-walk no-repeat guarantee when the caller
/// walks a cursor forward through it.
List<ScripturePrompt> rankScripturePrompts({
  required List<ScripturePrompt> library,
  ScriptureHistory history = const ScriptureHistory.empty(),
  DevotionalCategory? preferred,
  Duration cooldown = const Duration(days: 30),
  DateTime? now,
  math.Random? random,
}) {
  if (library.isEmpty) return const [];

  final clock = now ?? DateTime.now();
  final shuffle = random ?? math.Random();
  final restingUntil = clock.subtract(cooldown);

  // Theme first, everything else after — the two blocks are ranked separately
  // and never interleaved, so choosing a theme still means working through it.
  final themed = <ScripturePrompt>[];
  final others = <ScripturePrompt>[];
  for (final prompt in library) {
    (preferred != null && prompt.category == preferred ? themed : others)
        .add(prompt);
  }

  // Within each block: unseen, then long-unseen, with the resting ones set
  // aside. The resting lists from *both* blocks go behind *both* bodies, not
  // behind their own block — an unseen passage from outside the theme is a
  // better answer than an on-theme one from yesterday, and the promise that
  // yesterday's verse does not return today is the stronger of the two.
  final themedBody = <_Ranked>[];
  final themedResting = <_Ranked>[];
  final otherBody = <_Ranked>[];
  final otherResting = <_Ranked>[];

  _partition(themed, history, shuffle, restingUntil, themedBody, themedResting);
  _partition(others, history, shuffle, restingUntil, otherBody, otherResting);

  return [
    ..._spread(themedBody),
    ..._spread(otherBody),
    // The fallback tail, oldest first across both blocks. Reached only by a
    // walk that has outlasted the entire library, and ordered so that even then
    // the passage returning is the one longest ago rather than the one just
    // delivered.
    ..._spread([...themedResting, ...otherResting]..sort(_byLastSeen(history))),
  ];
}

/// Splits one block into "may be delivered now" and "still resting", each
/// already in draw order.
void _partition(
  List<ScripturePrompt> prompts,
  ScriptureHistory history,
  math.Random shuffle,
  DateTime restingUntil,
  List<_Ranked> body,
  List<_Ranked> resting,
) {
  final unseen = <ScripturePrompt>[];
  final seen = <ScripturePrompt>[];

  for (final prompt in prompts) {
    (history.hasSeen(prompt.id) ? seen : unseen).add(prompt);
  }

  unseen.shuffle(shuffle);
  seen.sort(_byLastSeenPrompts(history));

  body.addAll([for (final p in unseen) _Ranked(p, scriptureBookOf(p))]);
  for (final prompt in seen) {
    final last = history.lastSeen(prompt.id);
    final ranked = _Ranked(prompt, scriptureBookOf(prompt));
    // `isAfter` rather than `!isBefore`: a passage delivered at this exact
    // instant is resting, which only a test will ever construct.
    (last != null && last.isAfter(restingUntil) ? resting : body).add(ranked);
  }
}

/// Oldest sighting first. A prompt with no record sorts to the front, which
/// cannot happen inside `_partition` but makes the comparator safe to reuse.
int Function(ScripturePrompt, ScripturePrompt) _byLastSeenPrompts(
  ScriptureHistory history,
) {
  return (a, b) {
    final left = history.lastSeen(a.id);
    final right = history.lastSeen(b.id);
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    return left.compareTo(right);
  };
}

int Function(_Ranked, _Ranked) _byLastSeen(ScriptureHistory history) {
  final compare = _byLastSeenPrompts(history);
  return (a, b) => compare(a.prompt, b.prompt);
}

/// Nudges the queue so a walk does not become four consecutive laments, or
/// four consecutive Psalms.
///
/// Freshness is not only about repeats: a walk can deliver eight passages none
/// of which the member has ever seen and still feel monotonous, because Psalms
/// is the largest book in the library and the register is recognisable. This
/// pass looks a short way down the queue and prefers the first candidate that
/// differs from what just went out — by book and category if it can, by book
/// alone if it cannot, by category alone failing that.
///
/// **A preference, never a filter.** If nothing inside the window differs it
/// takes the head of the queue unchanged, so this can slow variety down but can
/// never starve delivery or drop a passage. The ranking it reorders has already
/// been earned; [kVarietyWindow] bounds how far that ranking can be distorted.
List<ScripturePrompt> _spread(List<_Ranked> ranked) {
  if (ranked.length < 3) return [for (final r in ranked) r.prompt];

  final remaining = List<_Ranked>.of(ranked);
  final ordered = <ScripturePrompt>[];
  String? lastBook;
  DevotionalCategory? lastCategory;

  while (remaining.isNotEmpty) {
    final window = math.min(kVarietyWindow, remaining.length);
    var pick = 0;

    if (lastBook != null) {
      pick = -1;
      // Tried in order of how much they matter: a repeated book is the more
      // visible sameness, so the book-only tier outranks the category-only one.
      for (final test in <bool Function(_Ranked)>[
        (r) => r.book != lastBook && r.prompt.category != lastCategory,
        (r) => r.book != lastBook,
        (r) => r.prompt.category != lastCategory,
      ]) {
        for (var i = 0; i < window; i++) {
          if (test(remaining[i])) {
            pick = i;
            break;
          }
        }
        if (pick >= 0) break;
      }
      // Everything in reach looks like what just went out. Take the head rather
      // than search the whole queue: this is a preference, and the queue order
      // behind it is the one that was earned.
      if (pick < 0) pick = 0;
    }

    final chosen = remaining.removeAt(pick);
    ordered.add(chosen.prompt);
    lastBook = chosen.book;
    lastCategory = chosen.prompt.category;
  }

  return ordered;
}
