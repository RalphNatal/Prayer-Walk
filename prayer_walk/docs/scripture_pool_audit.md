# Scripture pool audit

**Date:** 29 July 2026
**Scope:** the prompt library behind *scripture on the trail* — what is in it, what
edition it is in, and how quickly a member sees the same passage twice.
**Status of this document:** a finding, not a plan. It changes nothing. What was
done about it is in the commit that follows.

Two complaints prompted this: *verses repeat across walks*, and *nothing is NLT
yet*. Both are real. This report gives the numbers rather than the impression.

---

## 1. Translation status

### 1.1 The counts

| Source | Rows | WEBBE | NLT | No translation |
|---|---:|---:|---:|---:|
| `supabase/seed/scripture_prompts_seed.sql` | 47 | 41 | **0** | 6 |
| `assets/scripture/prompts.json` (bundled) | 47 | 41 | **0** | 6 |
| `supabase/seed/devotionals_seed.sql` | 8 | 8 † | **0** | 0 |
| **Total quoted passages** | **55** | **49** | **0** | **6** |

† The devotionals seed does not write a `translation` value at all. The column is
added later by `20260728070000_devotional_translation.sql`, whose backfill sets
`'WEBBE'` on every row with non-empty `scripture_text` — which is all eight. So
they are WEBBE by migration rather than by seed.

The six rows with no translation are `kind = 'prayer'`: *Before the first mile*,
*On the way home*, *Carrying someone*, *The Jesus Prayer*, *Fewer words*, and
*Anima Christi*. They quote no edition, so they carry an empty `translation`
deliberately and are delivered on a walk whatever edition is configured.

### 1.2 The plain answer

**There is no NLT text anywhere in this repository, and there never has been.**
Not in the seeds, not in the bundled asset, not in a migration, not in a
fixture. `AppConfig.scriptureTranslation` defaults to `'WEBBE'`, so an
unconfigured build delivers WEBBE, which is exactly what is seeded.

### 1.3 What *does* exist — a correction to the brief

The brief states there is "no NLT seed template". That is not accurate. Two
templates exist and are complete:

- `supabase/seed/scripture_prompts_nlt_seed.sql.template` — 41 references, all
  six categories, sort order preserved, `translation` set to `'NLT'`, every body
  left as `<<PASTE LICENSED NLT TEXT HERE>>`.
- `supabase/seed/devotionals_nlt_seed.sql.template` — the same for the eight
  devotional passages.

Both already carry Tyndale's copyright notice, the 500-verse / 25% / no-complete-book
limits, the mandatory credit line, the `permission@tyndale.com` contact, and a
SQL snippet that counts NLT rows against the ceiling. The prompt template also
guards itself: `where v.body not like '<<PASTE%'` means running it as committed
inserts **zero rows**, and running it half-filled inserts only what has actually
been pasted.

So the accurate statement is not *"the NLT support work has not been run"* but
*"the NLT support work is built and waiting on one manual step"* — the paste of
licensed text by the maintainer. Nothing in code, schema or tooling is missing.

Two pieces of drift found in the template header while checking it:

- it says "7 `kind = 'prayer'` rows" are excluded; there are **6**.
- it says "41 references, about 46 verses"; that is right for the scripture rows,
  but the file's own combined estimate of "about 60 verses" against the 500
  ceiling should be re-derived after any pool expansion.

### 1.4 Runtime behaviour today

`SupabaseScriptureRepository._inTranslation` filters the library to the
configured edition, but falls back to delivering *everything* if that leaves no
scripture at all. On an NLT build with no NLT rows seeded — the current state —
a walk therefore delivers the WEBBE set and credits it WEBBE. That is the
correct failure direction: a walk with the wrong edition is a disappointment, a
walk with nothing to read is the failure the feature exists to avoid.

---

## 2. Pool size and consumption

### 2.1 The pool

**47 prompts** are available to an unfiltered walk: 41 scripture and 6 prayers.
The seed and the bundled asset agree exactly, so an offline device and a synced
device draw from the same 47.

### 2.2 Configured cadences

| Preset | Distance | Steps |
|---|---:|---:|
| Gentle (**default**) | 400 m | ~500 |
| Spacious | 800 m | ~1000 |
| Custom | 200–2000 m (slider); clamped 200–5000 m in the controller | — |

Step cadence maps to distance at 0.8 m/stride, so it consumes at the same rate.

### 2.3 What a walk consumes

Arrivals = `floor(distance / interval)`. Nothing arrives at the start line.

| Walk | Gentle (400 m) | Spacious (800 m) | Custom min (200 m) |
|---|---:|---:|---:|
| 3 km | **7** | 3 | 15 |
| 5 km | **12** | 6 | 25 |
| 10 km | **25** | 12 | 50 |

Two things fall out of this immediately:

- A 10 km walk at the 200 m custom interval consumes **50** prompts from a pool
  of 47. That walk already exhausts the library and reshuffles *within itself*
  today — the one case where the current code's "reshuffle rather than go quiet"
  path fires on a single walk.
- A 10 km walk at the default cadence consumes **53%** of the entire library in
  one outing.

### 2.4 Themed walks are much thinner

Choosing a theme does not filter the pool — `_refillPool` puts the preferred
category first and everything else after it. So a themed walk works through its
theme and then drifts off it rather than going silent. The theme therefore lasts
only as long as its own count:

| Theme | Prompts | Theme lasts (gentle) |
|---|---:|---|
| Scripture walk | 10 | 4 km |
| Intercession | 8 | 3.2 km |
| Lament | 8 | 3.2 km |
| Morning light | 7 | 2.8 km |
| Gratitude | 7 | 2.8 km |
| Stillness | 7 | 2.8 km |

**A 5 km "Stillness" walk stops being a stillness walk after 2.8 km.** That is a
distinct complaint from the repeat problem and is not fixed by history alone —
it is fixed by more prompts per theme.

---

## 3. Repeat mathematics

### 3.1 Why it repeats — confirmed

`RecordingController` shuffles the library without replacement and walks a cursor
forward, which correctly guarantees no repeat *within* one walk. But
`_armScripture` (`recording_controller.dart:551-553`) and the teardown
(`:846-848`) reset `_library`, `_pool` and `_cursor` to empty. Every walk
therefore reshuffles all 47 from scratch with no memory of what came before.
Each walk is an independent uniform draw.

This is arithmetic, not a broken shuffle. The fix is history, not a better
random number generator.

### 3.2 Current logic — probability of a repeat by the second walk

Two independent draws of *k* prompts from *N* = 47:

| Walk length | Prompts drawn | P(second walk repeats something from the first) |
|---|---:|---:|
| 3 km | 7 | **70.4%** |
| 5 km | 12 | **98.4%** |
| 10 km | 25 | **100%** (certain — 25 + 25 > 47) |

Expected number of walks before a member sees any passage twice, at the default
cadence: **2.3 walks** (3 km), **2.0 walks** (5 km), **2.0 walks** (10 km).

The complaint is not that repeats happen within two or three walks. It is that
at 5 km they are all but guaranteed on the *second* walk, and at 10 km they are
mathematically unavoidable.

### 3.3 With cross-walk history — unseen-first

With a delivery record, a prompt only repeats once the member has genuinely seen
everything. Walks of fresh verses ≈ `N / k`:

| Pool | 3 km (7/walk) | 5 km (12/walk) | 10 km (25/walk) |
|---|---:|---:|---:|
| **47** (today) | 6 walks | 3 walks | 1 walk |
| **200** | 28 walks | 16 walks | 8 walks |
| **350** | 50 walks | 29 walks | 14 walks |
| **500** (ceiling) | **71 walks** | **41 walks** | 20 walks |

Read against a daily walker at 5 km: today's 47 gives **three days**. History
alone at 47 gives three days and then starts recycling. History at 350 gives
**about a month**; at 500, **about six weeks** — and after that it is
least-recently-seen ordering rather than repetition, so the passage returning is
the one last seen six weeks ago, not the one from Tuesday.

**Neither fix works alone.** History without a bigger pool buys three days at
5 km. A bigger pool without history still repeats on walk two. Both are needed.

### 3.4 The ceiling this collides with

Tyndale permits up to **500 NLT verses** without express written permission (and
not more than 25% of the work, and no complete book). A year of daily 5 km
walking with no repeat at all would need ~4,400 verses — nearly nine times the
free ceiling.

So *"fresh, never-repeating verses"* and *"NLT"* cannot both be satisfied
without a licence conversation. What 500 well-rotated prompts buys is roughly
six weeks of daily 5 km walking before anything returns, and considerably longer
in practice because most members do not walk daily and least-recently-used
ordering means the return is a passage from a month and a half ago.

**Anything beyond 500 NLT verses requires written permission from Tyndale
(permission@tyndale.com).** That is a stakeholder decision, not an engineering
one, and it is not designed around here.

---

## 4. Distribution

### 4.1 By category

Counting all 47, prayers included:

| Category | Count | Share |
|---|---:|---:|
| Scripture walk | 10 | 21% |
| Intercession | 8 | 17% |
| Lament | 8 | 17% |
| Morning light | 7 | 15% |
| Gratitude | 7 | 15% |
| Stillness | 7 | 15% |

Reasonably even. Scripture walk is over-weighted, but not damagingly so. The
problem here is not balance, it is absolute size — see §2.4.

### 4.2 By book

21 of the canon's 66 books are represented across the 41 scripture rows:

| Book | Count |
|---|---:|
| **Psalms** | **17 (41%)** |
| Isaiah | 3 |
| Matthew | 2 |
| James | 2 |
| 17 books at one verse each | 17 |

The seventeen singles: Genesis, Deuteronomy, 1 Kings, Proverbs, Lamentations,
Micah, Habakkuk, Mark, Luke, Romans, 2 Corinthians, Galatians, Ephesians,
Philippians, Colossians, 1 Thessalonians, 1 Timothy.

### 4.3 Where the set is thin

**Psalms is 41% of the scripture pool.** The brief's worry about "60% Psalms"
is not quite reached, but two passages in five coming from one book is enough to
make a walk feel same-y even when no verse technically repeats. A member who
walks four times a week will hear the Psalter's register almost every time.

Whole regions of the canon are absent:

- **No John.** The Gospel most quoted in devotional use is not in the library at
  all. Neither is Acts.
- **No Hebrews, 1 Peter, 1 John, or Revelation** — the entire back half of the
  New Testament is unrepresented apart from James.
- **No wisdom literature beyond one Proverbs verse.** No Job, no Ecclesiastes,
  no Song of Songs — which removes the register best suited to lament and to
  walking in silence.
- **No Jeremiah, Ezekiel, Daniel, Hosea, Joel, Amos, Jonah, Zephaniah,
  Zechariah, Malachi.** Isaiah carries the prophets alone.
- **Almost no narrative Old Testament.** One Genesis verse (Enoch walking with
  God) and one Deuteronomy verse. No Exodus, Joshua, Ruth, Samuel, Nehemiah.
- **The Gospels are thin**: two Matthew, one Mark, one Luke, no John. Four
  verses of Gospel in a library of 41.

### 4.4 What that implies for the expansion

Growth should not be proportional. Adding Psalms in proportion would preserve
the 41% and preserve the complaint. The expansion should:

- hold Psalms to roughly **20%** of the enlarged pool — still the single largest
  book, which is right for a walking prayer app, but no longer dominant;
- open **John, Acts, Hebrews, 1 Peter, 1 John and Revelation**;
- open the **wisdom books** (Job, Ecclesiastes, Song of Songs) for lament and
  stillness;
- carry the **minor prophets**, which are almost entirely missing and are short,
  vivid and well-suited to a single glance;
- bring the **Gospels** up to a share proportionate to their devotional use;
- and lift every category to a size where a themed 5 km walk stays on its theme
  the whole way — which at the default cadence means **at least 12 prompts per
  theme**, and comfortably more.

---

## 5. Summary of findings

1. **Zero NLT text exists.** The templates, the schema, the per-row `translation`
   column, the credit-line plumbing and the ceiling counter are all built. One
   manual paste of licensed text is the only outstanding step. The brief's
   assumption that the template is missing is incorrect.
2. **The pool is 47 prompts.** A 10 km walk at the default cadence consumes over
   half of it in one outing.
3. **Repeats are certain, not likely.** 98.4% probability of a repeat on the
   second 5 km walk. The cause is the per-walk `_pool`/`_cursor` reset, not the
   shuffle.
4. **History alone is not enough.** At 47 prompts it buys three days of daily
   5 km walking. The pool must grow with it.
5. **Psalms is 41% of the library and 45 books are absent entirely**, including
   John, Acts, Hebrews and all wisdom literature.
6. **Themed walks run off-theme after 2.8 km** because no theme holds more than
   10 prompts.
7. **500 NLT verses is a hard ceiling** without written permission from Tyndale.
   At 500 prompts a daily 5 km walker sees roughly six weeks of unrepeated
   passages. Longer freshness than that is a licensing decision, not an
   engineering one.

---

## Appendix — the state after the fix

Added after the changes described above were made, so the before-and-after sits
in one document. Everything above §5 describes the library as it was on
29 July 2026 before any change.

### Pool

| | Before | After |
|---|---:|---:|
| Prompts | 47 | **319** |
| Scripture | 41 | 301 |
| Prayers | 6 | 18 |
| Distinct books | 21 | **59** |
| Psalms share of scripture | 41% | **26%** |
| Smallest theme | 7 | **53** |

Every theme now holds 53 or 54 prompts, so a themed walk stays on its theme for
21 km at the default cadence rather than 2.8 km.

### Walks until a repeat, measured

Unseen-first selection means a repeat is impossible until the pool is spent, so
this is `floor(319 / prompts per walk)`:

| Walk | Before (per-walk shuffle) | After |
|---|---|---:|
| 3 km (7/walk) | repeat ~70% likely on walk 2 | **45 walks** |
| 5 km (12/walk) | repeat 98.4% likely on walk 2 | **26 walks** |
| 10 km (25/walk) | repeat certain on walk 2 | **12 walks** |

For a daily 5 km walker that is roughly **26 days** of entirely new passages,
after which the least-recently-seen ordering returns the one last seen nearly a
month ago rather than one from Tuesday. The 30-day cooldown means nothing seen
inside the last month is reached at all while anything else remains.

Asserted rather than asserted-about: `scripture_delivery_test.dart` drives the
recorder through ten consecutive walks against a library of 70 and requires all
sixty draws to be distinct. It fails on walk two against the old code.

### The NLT position, restated

The expanded library brings the NLT template to **301 references ≈ 334 verses**,
plus 14 in the devotionals template — about **348 of the 500** that may be
quoted without written permission. Roughly 152 verses of headroom, which is
about 25 more passages per theme.

The template can therefore still be filled in completely today. **The next
expansion of the library cannot be.** At that point the choice is a partial NLT
fill (supported: unfilled rows are skipped, and those passages are delivered as
WEBBE instead) or written permission from `permission@tyndale.com`.

Note what did not change: the bundled asset stays WEBBE whatever
`SCRIPTURE_TRANSLATION` says, because shipping licensed text inside the binary
is a wider distribution question than a row on a server and is still unanswered.

### Text accuracy — an open item

The 274 added WEBBE passages were selected and transcribed for this library
rather than pulled programmatically from a source file. Public domain means no
fee is owed, not that a transcription error is acceptable in somebody's prayer.
**Diff `supabase/seed/scripture_prompts_seed.sql` against
<https://ebible.org/webbe/> before seeding a parish**, and treat any mismatch as
this repository being wrong. The seed header carries the same warning.
