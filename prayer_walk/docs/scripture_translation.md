# Which translation is Prayer Walk serving?

Short answer, in one place: **the `SCRIPTURE_TRANSLATION` value in `env.json`**,
compiled in through `AppConfig.scriptureTranslation`. Everything else follows
from it.

This document exists because "why aren't these the verses I configured?" took a
trace through five files to answer, and it should take one glance.

---

## The one-glance answer

Run a debug build, open **Settings → Scripture on the trail**, and read the
**Translation diagnostic** panel at the bottom. It reports three things:

| Line | What it tells you |
| --- | --- |
| **Configured default** | What `SCRIPTURE_TRANSLATION` is set to. |
| **Loaded from** | `network`, `cache`, or `bundled asset`. |
| **Available** | How many prompts of each edition the source held — *before* the edition filter. `NLT 0` means the licensed rows are not there. |
| **Delivering** | What a walk is actually handing out. Not always the configured default. |

The panel is `kDebugMode`-only and builds to nothing in release. The honest half
of it — the edition named under every passage — ships to walkers instead.

`Loaded from: bundled asset` is worth knowing on sight. The asset shipped inside
the binary is **always public-domain WEBBE**, whatever the build is configured
to deliver, so a device that fell that far back reads WEBBE and says WEBBE. That
is by design, not a bug, and it is the single most likely reason a walker sees
an edition they did not choose.

## Where the decision is actually made

```
env.json  SCRIPTURE_TRANSLATION
  └─ AppConfig.scriptureTranslation           (compile-time, defaults 'WEBBE')
      └─ appTranslationProvider               → BibleTranslation
          └─ scriptureRepositoryProvider      passes the id in
              └─ SupabaseScriptureRepository._translation
                  └─ _inTranslation()         ← the filter that decides
                      └─ ScriptureLibrary     ← prompts + provenance
```

`_inTranslation` keeps a prompt when it is in the configured edition **or** it
quotes nobody (a prayer belongs to every edition). If that leaves no scripture
at all, it delivers the whole library instead and logs a `[PW-SCRIP][WARN]`
naming both editions. A walk with the wrong edition is a disappointment; a walk
with nothing to read is the failure the feature exists to avoid.

## Why every verse names its edition

Two different obligations, deliberately kept apart:

* **The mark** — `(NLT)` after every quotation. A licence condition. It is
  written into the text by `BibleTranslation.attributed()`, which is the only
  way a quotation becomes displayable, so no screen and no setting can drop it.
  `showTranslation` has no authority over it.
* **The credit label** — `WEBBE`, `NLT`, `Public domain` under the passage. A
  courtesy, and a diagnostic. The walker can switch it off. It is never blank:
  a blank line under a verse looks exactly like a verse that came from
  somewhere else entirely, which is how a fallback goes unnoticed.

Surfaces, and the widget each uses:

| Surface | Draws through |
| --- | --- |
| Arrival card, expanded reading | `ScriptureBody` → `ScriptureQuotation` + `TranslationCredit` |
| Live delivered list | `ScriptureQuotation` |
| Devotional reader | `ScriptureQuotation` + `TranslationCredit` |
| Admin list, submissions queue, my submissions | `ScriptureQuotation` |
| **Summary and detail waypoint lists** | `MarkedQuotation` |

The last row is the odd one. A scripture waypoint's note is JSONB on
`activities` with no `translation` column beside it, so by the time a list draws
it there is nothing left but a string. `RecordingController` attributes it on
the way in, at the one moment the edition is still known, and `MarkedQuotation`
reads that mark back out with `BibleTranslation.declaredIn()`. Unmarked text
claims no edition rather than guessing one — it is labelled `Public domain`,
which is true both of WEBBE and of a prayer.

`scripture_attribution_test.dart` fails the build if a new screen reaches around
these widgets to draw a quotation itself.

---

## Converting the library to the NLT

Six steps. Steps 2 and 5 are the maintainer's alone.

### 1. Copy the template

```bash
cd prayer_walk/supabase/seed
cp scripture_prompts_nlt_seed.sql.template scripture_prompts_nlt_seed.sql
cp devotionals_nlt_seed.sql.template       devotionals_nlt_seed.sql
```

Drop the `.template` suffix. **Think hard before committing the filled copies**
— they hold licensed text, and a public repository is a wider distribution than
a row on a server.

The references, categories and sort orders are already there: that selection is
curatorial work that was done once and should not be redone.

### 2. Paste the licensed text over each placeholder

Every body reads `'<<PASTE LICENSED NLT TEXT HERE>>'`. Replace the placeholder
*inside* the quotes, from a licensed source, by hand.

* **Double every apostrophe.** SQL string literals escape `'` as `''`. A verse
  containing `Lord's` must be typed `Lord''s` or the statement will not parse.
* **Leave `translation` as `'NLT'`** on every row.
* Do not change the references. If a passage should not be quoted in NLT, leave
  its placeholder alone — see step 4.

### 3. Count before you seed

```bash
psql "$DATABASE_URL" -f nlt_ceiling_count.sql
```

Or paste it into the Supabase SQL editor. It is read-only.

Tyndale allows up to **500 verses**, and not more than 25% of the work, and no
complete book. The template's own header estimates the full prompt set at about
334 verses and the devotional set at about 14 — roughly 348 combined, leaving
about 152 verses of headroom. That is enough to fill the current library
completely, and not enough to survive the next expansion of it.

`approx_verses` is a floor: it expands `5:16-18` into three but reads
`Psalm 1:1,3` as one. Count by hand before going near the limit, and read the
"no complete book" check at the foot of the counter file — a short book like
Jude or Philemon could be quoted whole while the headroom still looks healthy.

### 4. A partial fill is a supported state

Rows still holding a placeholder are skipped by `where v.body not like '<<PASTE%'`
at the foot of the seed. Filling in a subset is normal, not broken.

Prefer breadth over depth: take passages from every category, so an NLT walk is
not four laments in a row. Passages left unfilled are still delivered — as
WEBBE, from the rows the public-domain seed inserted, each carrying its own
credit.

### 5. Run the seed

```bash
psql "$DATABASE_URL" -f scripture_prompts_nlt_seed.sql
psql "$DATABASE_URL" -f devotionals_nlt_seed.sql
```

Both are idempotent on `(reference, translation)`, so re-running after filling
in more verses adds the new ones without duplicating the old.

Then run `nlt_ceiling_count.sql` again and confirm the number is what you
expected.

### 6. Switch the default

In `env.json`:

```json
"SCRIPTURE_TRANSLATION": "NLT"
```

Rebuild. Nothing else changes: both editions live in `scripture_prompts` at
once, each row carrying its own `translation`, and the build decides which is
delivered. Verify in the debug diagnostic that **Available** now shows a
non-zero `NLT` and **Delivering** says `NLT`.

To go back, set it to `WEBBE`. No content is rewritten either way.

---

## What does not change, ever

* **The bundled asset stays WEBBE.** `assets/scripture/prompts.json` is
  public-domain text and remains so unless written permission covering text
  shipped *inside the binary* is confirmed — a wider distribution question than
  a row on a server, and one this project has not asked. A device that falls
  back to it reads WEBBE and is credited WEBBE; nothing there inherits NLT's
  mark. Asserted by `scripture_attribution_test.dart`.
* **The WEBBE rows stay in the table.** They are the fallback, the offline
  floor, and the licence-free baseline. The NLT seed adds rows; it replaces
  nothing.
* **The `(NLT)` mark cannot be switched off.** Not by `showTranslation`, not by
  a screen, not by an admin. It is inside the text.
* **The Tyndale credit line is verbatim.** `BibleTranslation.nlt.creditLine` is
  the only place it is written down, and a test compares it character for
  character. It appears in Settings → Scripture credits and on the app's licence
  page.

## The five things that can go wrong, and how to tell them apart

| Symptom | Diagnostic reads | Fix |
| --- | --- | --- |
| Licensed rows never seeded | `Available: WEBBE n · NLT 0` | Steps 1–5 above |
| Default never switched | `Configured default: WEBBE` | Step 6 |
| Filter not filtering | `Delivering: NLT, WEBBE` | A bug in `_inTranslation` — it should never report two editions |
| Device is offline / sync failed | `Loaded from: bundled asset` or `cache` | Expected. The asset is WEBBE by design |
| Rows are right, walker cannot tell | — | Fixed: every surface names its edition |
