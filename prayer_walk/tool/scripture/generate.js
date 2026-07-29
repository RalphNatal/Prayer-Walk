// The one source the scripture library is generated from.
//
//   node tool/scripture/generate.js
//
// Emits three files that must agree with each other and previously did not have
// to:
//
//   supabase/seed/scripture_prompts_seed.sql          — the WEBBE library
//   assets/scripture/prompts.json                     — the offline floor
//   supabase/seed/scripture_prompts_nlt_seed.sql.template — structure only
//
// They are generated rather than hand-maintained because the seed's own header
// used to end with "keep the two in step if you edit one", which is an
// instruction that works until somebody is in a hurry. Three hundred passages
// is well past the point where that holds.
//
// The passages themselves live in the six theme files beside this one. Edit
// those, re-run this, and commit all three outputs together.
//
// ⚠️ This script must never be taught to emit NLT text. The template it writes
// contains placeholders only, and it asserts that before writing — see the
// checks at the foot of the NLT section. Licensed text is pasted by the
// maintainer into a copy of the template, and that copy is not committed.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');

const CATEGORIES = [
  ['morningLight', 'morning light', require('./morning.js')],
  ['gratitude', 'gratitude', require('./gratitude.js')],
  ['intercession', 'intercession', require('./intercession.js')],
  ['lament', 'lament', require('./lament.js')],
  ['stillness', 'stillness', require('./stillness.js')],
  ['scriptureWalk', 'scripture walk', require('./walk.js')],
];

// ---------------------------------------------------------------- build ----

const prompts = [];
let base = 0;
for (const [category, , rows] of CATEGORIES) {
  base += 1000;
  let n = 0;
  for (const [rawRef, body] of rows) {
    n += 10;
    const isPrayer = rawRef.startsWith('PRAYER:');
    prompts.push({
      reference: isPrayer ? rawRef.slice('PRAYER:'.length) : rawRef,
      body,
      translation: isPrayer ? '' : 'WEBBE',
      kind: isPrayer ? 'prayer' : 'scripture',
      category,
      sort_order: base + n,
    });
  }
}

// ------------------------------------------------------------- validate ----

// Globally unique, not merely unique within a theme. The same passage under two
// category headings would be two prompt ids for one verse, which reads to a
// walker as exactly the repeat this whole change exists to remove — and history
// could not catch it, because the two ids are genuinely different.
const seenRef = new Map();
for (const p of prompts) {
  const key = p.reference;
  if (seenRef.has(key)) {
    throw new Error(
      `duplicate reference: ${key} in ${seenRef.get(key).category} and ${p.category}`
    );
  }
  seenRef.set(key, p);
  if (!p.body.trim()) throw new Error(`empty body: ${p.reference}`);
  if (p.body.length > 240) throw new Error(`too long (${p.body.length}): ${p.reference}`);
}

// Guardrail: no licensed edition may appear anywhere in the generated content.
const FORBIDDEN = /\b(NLT|NIV|ESV|NASB|CSB|New Living Translation)\b/;
for (const p of prompts) {
  if (FORBIDDEN.test(p.body) || FORBIDDEN.test(p.reference)) {
    throw new Error(`licensed edition named in content: ${p.reference}`);
  }
  if (p.translation !== 'WEBBE' && p.translation !== '') {
    throw new Error(`unexpected translation: ${p.translation}`);
  }
}

const scripture = prompts.filter((p) => p.kind === 'scripture');
const prayers = prompts.filter((p) => p.kind === 'prayer');

// ------------------------------------------------------------------ SQL ----

const q = (s) => `'${s.replace(/'/g, "''")}'`;
const wrap = (body, indent) => {
  // Long bodies stay on one line; SQL has no length problem and a wrapped
  // string literal is harder to diff than a long one.
  return q(body);
};

function sqlRows(list) {
  const out = [];
  let currentCategory = null;
  for (const p of list) {
    if (p.category !== currentCategory) {
      currentCategory = p.category;
      const label = CATEGORIES.find((c) => c[0] === p.category)[1];
      const dashes = '-'.repeat(Math.max(2, 72 - label.length));
      out.push(`\n  -- ${dashes} ${label} --`);
    }
    out.push(
      `  (${q(p.reference)},\n   ${wrap(p.body)},\n   ${q(p.translation)}, ${q(p.kind)}, ${q(p.category)}, ${p.sort_order}),`
    );
  }
  const last = out.length - 1;
  out[last] = out[last].replace(/,$/, '');
  return out.join('\n');
}

const seedHeader = `-- ===========================================================================
-- SEED — run once, by hand, by the maintainer. NOT a migration.
-- ===========================================================================
--
-- This file is deliberately not in \`supabase/migrations/\`. It is content, not
-- schema: re-running a migration must be safe on every project, whereas this
-- is a starting library that an admin is expected to edit, extend and prune
-- from the admin screens afterwards. Paste it into the Supabase SQL editor
-- after \`20260727020000_scripture_prompts.sql\` has been applied.
--
-- It is idempotent — a prompt with the same reference and translation is
-- skipped — so running it twice does not duplicate the library, and running it
-- again after an expansion adds only what is new.
--
-- SIZE, AND WHY IT IS THIS SIZE
-- ------------------------------
-- ${prompts.length} prompts: ${scripture.length} scripture and ${prayers.length} prayers.
--
-- The library used to hold 47. At the default cadence a 5 km walk delivers
-- twelve of them, so two walks drawn independently from 47 collided 98% of the
-- time — see \`docs/scripture_pool_audit.md\`. Delivery history fixed the
-- *ordering* (unseen first, then least recently seen); this file fixes the
-- *arithmetic*. At this size a daily 5 km walker gets roughly a month before
-- any passage returns, and when one does it is the one longest unseen.
--
-- It is deliberately not larger. The licensed New Living Translation edition
-- of this same set is capped at 500 verses without written permission from
-- Tyndale, and a WEBBE library the NLT one cannot match would mean the two
-- editions delivering different walks. Grow both together, or neither.
--
-- LICENSING
-- ---------
-- Every scripture row below is the World English Bible, British Edition
-- (WEBBE): public domain, no licence fee, no attribution obligation. The
-- British edition is used rather than the base WEB because it renders the
-- divine name as "the LORD" rather than "Yahweh", which is the form Catholic
-- usage expects.
--
-- ⚠️ VERIFY THE TEXT BEFORE A PRODUCTION SEED. The passages were selected and
-- transcribed for this library rather than pulled programmatically from a
-- source file. Public domain means nobody is owed a fee, not that a
-- transcription error is acceptable in somebody's prayer. Diff this file
-- against https://ebible.org/webbe/ before seeding a parish, and treat any
-- mismatch as this file being wrong.
--
-- Rows with kind = 'prayer' carry no translation: they are either ancient
-- formulas long in the public domain (the Jesus Prayer, Anima Christi, the
-- Kyrie) or written for this app.
--
-- Nothing here is drawn from the NIV, ESV, NLT, NASB or CSB. Those are
-- copyrighted. Do not paste any of them into *this* file — it is the
-- public-domain set, and it is also what gets bundled into the binary.
--
-- Licensed New Living Translation rows have their own file:
-- \`scripture_prompts_nlt_seed.sql.template\`, which carries Tyndale's terms, the
-- 500-verse ceiling and the credit line. Both editions can live in this table
-- at once; \`SCRIPTURE_TRANSLATION\` decides which one a walk delivers. This set
-- is never replaced — it is the fallback, and the licence-free baseline the app
-- returns to if the licensed rows are ever pulled.
--
-- The same set ships as \`assets/scripture/prompts.json\`, which is the offline
-- floor when a device has never synced, and which stays WEBBE whatever the app
-- is configured to deliver. Both files are generated from one source; if you
-- edit one by hand, edit the other to match.

insert into public.scripture_prompts
  (reference, body, translation, kind, category, sort_order)
select v.reference, v.body, v.translation, v.kind, v.category, v.sort_order
from (values`;

const seedFooter = `
) as v(reference, body, translation, kind, category, sort_order)
-- Idempotent on reference + edition, so a second run after an expansion adds
-- the new passages without duplicating the old ones.
where not exists (
  select 1
  from public.scripture_prompts p
  where p.reference = v.reference and p.translation = v.translation
);

-- What landed, by theme — run after seeding to confirm the spread.
--
--   select category, kind, count(*)
--     from public.scripture_prompts
--    where translation in ('WEBBE', '')
--    group by category, kind
--    order by category, kind;
`;

fs.writeFileSync(
  path.join(ROOT, 'supabase/seed/scripture_prompts_seed.sql'),
  seedHeader + '\n' + sqlRows(prompts) + seedFooter,
  'utf8'
);

// ---------------------------------------------------------------- asset ----

const asset = {
  note:
    'The offline floor for scripture on the trail. Shipped with the app so a walk with no signal and no cached sync still has something to read. Refreshed from public.scripture_prompts whenever the device is online.',
  licence:
    "Scripture text is the World English Bible, British Edition (WEBBE) — public domain, no licence fee and no attribution obligation. The British edition is used rather than the base WEB because it renders the divine name as 'the LORD', which is the form Catholic usage expects. Prayers marked kind='prayer' are either ancient formulas long in the public domain or written for this app. Nothing here is drawn from NIV, ESV, NLT, NASB or CSB. This set stays WEBBE whatever SCRIPTURE_TRANSLATION says the app delivers: bundling a licensed translation inside the binary is a wider distribution question than a row on a server, and it is unanswered. A device that falls back this far reads WEBBE and is credited WEBBE — each prompt carries its own translation, so nothing here inherits another edition's mark.",
  source: 'https://ebible.org/webbe/ — re-pull from there if byte-exact text is wanted.',
  prompts: prompts.map((p, i) => ({
    id: `sp_${String(i + 1).padStart(3, '0')}`,
    reference: p.reference,
    body: p.body,
    translation: p.translation,
    kind: p.kind,
    category: p.category,
    sort_order: p.sort_order,
  })),
};

fs.writeFileSync(
  path.join(ROOT, 'assets/scripture/prompts.json'),
  JSON.stringify(asset, null, 2) + '\n',
  'utf8'
);

// ----------------------------------------------------------- NLT template ---

const PLACEHOLDER = '<<PASTE LICENSED NLT TEXT HERE>>';

// Verses per reference, ranges expanded, for the ceiling count.
function verseCount(ref) {
  const m = ref.match(/:\s*(\d+)\s*-\s*(\d+)\s*$/);
  if (m) return Math.max(1, Number(m[2]) - Number(m[1]) + 1);
  const c = ref.match(/:\s*([\d,]+)\s*$/);
  if (c && c[1].includes(',')) return c[1].split(',').length;
  return 1;
}
const nltVerses = scripture.reduce((sum, p) => sum + verseCount(p.reference), 0);
const DEVOTIONAL_VERSES = 14; // devotionals_nlt_seed.sql.template, ranges expanded
const combined = nltVerses + DEVOTIONAL_VERSES;

function nltRows(list) {
  const out = [];
  let currentCategory = null;
  for (const p of list) {
    if (p.category !== currentCategory) {
      currentCategory = p.category;
      const label = CATEGORIES.find((c) => c[0] === p.category)[1];
      const dashes = '-'.repeat(Math.max(2, 72 - label.length));
      out.push(`\n  -- ${dashes} ${label} --`);
    }
    out.push(
      `  (${q(p.reference)},\n   '${PLACEHOLDER}',\n   'NLT', 'scripture', ${q(p.category)}, ${p.sort_order}),`
    );
  }
  const last = out.length - 1;
  out[last] = out[last].replace(/,$/, '');
  return out.join('\n');
}

const nltHeader = `-- ===========================================================================
-- TEMPLATE — NOT RUNNABLE AS COMMITTED. The maintainer fills it in.
-- ===========================================================================
--
-- The WEBBE prompt library, restated as New Living Translation rows, with
-- every verse left blank. The structure is here — reference, kind, category,
-- sort order — because the *selection* is curatorial work that was already
-- done and should not be redone. The words are not here, and must not be added
-- by anyone but the maintainer, from a licensed source.
--
-- Copy to \`scripture_prompts_nlt_seed.sql\` (dropping \`.template\`) before
-- filling it in. The copy is git-ignored territory: think hard before
-- committing licensed text to a repository.
--
--
-- ⚠️ THE CEILING, AND HOW CLOSE THIS FILE IS TO IT
-- -------------------------------------------------
-- ${scripture.length} references, about ${nltVerses} verses once ranges are expanded.
-- Plus \`devotionals_nlt_seed.sql.template\`: about ${DEVOTIONAL_VERSES} verses.
-- Combined: about ${combined} verses, against a ceiling of 500.
-- Headroom: about ${500 - combined} verses.
--
-- This file CAN be filled in completely without written permission — but only
-- just, and only as it stands today. The margin is roughly ${500 - combined} verses, which is
-- about ${Math.floor((500 - combined) / 6)} more passages per theme and no more. The next expansion of the
-- library will cross the line.
--
-- When it does, there are two lawful options and no third:
--
--   (a) Fill in a SUBSET that stays under 500 verses. Every row left as a
--       placeholder is skipped by the \`where\` clause at the foot of this file,
--       so a partial fill is a supported state, not a broken one. Prefer
--       breadth: take passages from every category so an NLT walk is not four
--       laments in a row. A walk falls back to the whole library when the
--       configured edition has no rows, so the unfilled remainder is still
--       delivered — as WEBBE, carrying its own credit, rather than lost.
--
--   (b) Write to permission@tyndale.com and ask for permission covering the
--       full set. That is a conversation with a stakeholder, not a code change,
--       and it is the only way the licensed edition ever matches the
--       public-domain one passage for passage.
--
-- Do not fill in more than 500 verses' worth on the assumption that nobody
-- counts. Run the counter below before and after every fill.
--
-- Note what this ceiling means for the complaint that started all this. The
-- WEBBE library is public domain and can grow without limit; the NLT one
-- cannot. At 500 verses a daily 5 km walker sees roughly six weeks of
-- unrepeated passages before the least-recently-seen ordering starts returning
-- the oldest ones. "Never repeating" is not purchasable in NLT at any library
-- size without Tyndale's written permission.
--
--
-- COPYRIGHT
-- ---------
-- Holy Bible, New Living Translation, copyright © 1996, 2004, 2015 by Tyndale
-- House Foundation. All rights reserved.
--
-- WHAT MAY BE QUOTED WITHOUT EXPRESS WRITTEN PERMISSION
-- -----------------------------------------------------
--   * up to 500 verses, and
--   * not more than 25% of the work in which they are quoted, and
--   * no complete book of the Bible.
--
-- Written permission is required for quotations beyond those limits, and for
-- commentary or Bible-reference works produced for commercial sale. Requests
-- go to permission@tyndale.com.
--
-- THE CREDIT LINE, WHICH IS MANDATORY
-- ------------------------------------
-- The full notice must appear in the app, verbatim:
--
--   Scripture quotations are taken from the Holy Bible, New Living
--   Translation, copyright © 1996, 2004, 2015 by Tyndale House Foundation.
--   Used by permission of Tyndale House Publishers, Carol Stream, Illinois
--   60188. All rights reserved.
--
-- For non-salable media the short form is acceptable, in which case the
-- initials "(NLT)" must appear at the end of each quotation. Prayer Walk uses
-- the short form: the app appends "(NLT)" to every quotation automatically
-- (\`BibleTranslation.attributed\`) and renders the full notice above in
-- Settings → Scripture credits and on the licence page. Do not paste "(NLT)"
-- into the text below — it would be doubled.
--
-- OPEN QUESTION FOR THE MAINTAINER
-- ---------------------------------
-- Prayer Walk is software rather than print or an eBook, and Tyndale's
-- permission requirements differ for commercial products. Confirmation is
-- being sought from permission@tyndale.com on (a) whether express written
-- permission is needed for this use at all, and (b) whether any such
-- permission extends to text bundled inside the app binary. Until (b) is
-- answered yes, licensed text lives only in this table — never in
-- \`assets/scripture/prompts.json\`, which stays WEBBE and is what an offline
-- device reads.
--
-- HOW TO FILL THIS IN
-- --------------------
--   1. Copy each verse from an authorised NLT source you are licensed to use.
--      Do not type it from memory, do not copy it from an unlicensed site, and
--      do not ask an AI assistant to supply it — none of those is a licensed
--      source, and the last one is how unlicensed text gets committed by
--      accident.
--   2. Replace the chosen \`${PLACEHOLDER}\` entries with that verse.
--   3. Double any apostrophe inside the text: \`don''t\`, not \`don't\`.
--   4. Leave \`translation\` as 'NLT' on every row.
--   5. Stop before 500 verses. Run the counter below.
--
-- Rows whose body is still a placeholder are skipped by the \`where\` clause at
-- the foot of this file, so running it half-filled inserts only what has
-- actually been pasted, and running it unfilled inserts nothing at all.
--
-- THE CEILING COUNTER
-- --------------------
-- Licensed verses in use, both tables, ranges expanded:
--
--   with quoted as (
--     select reference from public.scripture_prompts where translation = 'NLT'
--     union all
--     select scripture_ref from public.devotionals where translation = 'NLT'
--   )
--   select
--     count(*) as rows,
--     sum(
--       case
--         when reference ~ ':\\s*\\d+\\s*-\\s*\\d+\\s*$'
--           then (regexp_replace(reference, '^.*:\\s*\\d+\\s*-\\s*(\\d+)\\s*$', '\\1'))::int
--              - (regexp_replace(reference, '^.*:\\s*(\\d+)\\s*-\\s*\\d+\\s*$', '\\1'))::int
--              + 1
--         else 1
--       end
--     ) as approx_verses,
--     500 - sum(
--       case
--         when reference ~ ':\\s*\\d+\\s*-\\s*\\d+\\s*$'
--           then (regexp_replace(reference, '^.*:\\s*\\d+\\s*-\\s*(\\d+)\\s*$', '\\1'))::int
--              - (regexp_replace(reference, '^.*:\\s*(\\d+)\\s*-\\s*\\d+\\s*$', '\\1'))::int
--              + 1
--         else 1
--       end
--     ) as remaining_before_permission_required
--   from quoted;
--
-- \`approx_verses\` is a floor: it expands \`5:16-18\` into three but reads
-- \`Psalm 1:1,3\` or a cross-chapter range as one. Count by hand before going
-- anywhere near 500, and note that "no complete book" is a separate condition
-- the query does not check at all.
--
-- WHAT IS NOT IN THIS FILE
-- -------------------------
-- The ${prayers.length} \`kind = 'prayer'\` rows from \`scripture_prompts_seed.sql\` are not
-- repeated here. They quote no translation — they are ancient formulas long in
-- the public domain, or written for this app — so they carry an empty
-- \`translation\` and are delivered on a walk whatever edition is configured.
-- Seeding them twice would duplicate them.
--
-- The WEBBE seed is not replaced by this file. It stays: it is the offline
-- asset, the fallback when the table cannot be reached, and the licence-free
-- baseline the app returns to if NLT rows are ever pulled.

insert into public.scripture_prompts
  (reference, body, translation, kind, category, sort_order)
select v.reference, v.body, v.translation, v.kind, v.category, v.sort_order
from (values`;

const nltFooter = `
) as v(reference, body, translation, kind, category, sort_order)
-- Placeholders are not content. An unfilled or half-filled run inserts only
-- what has actually been pasted, rather than seeding the library with the word
-- "PASTE" and delivering it on somebody's walk.
where v.body not like '<<PASTE%'
  -- Idempotent on reference + edition, so a second run after filling in more
  -- verses adds the new ones without duplicating the old.
  and not exists (
    select 1
    from public.scripture_prompts p
    where p.reference = v.reference and p.translation = v.translation
  );

-- After running this, set SCRIPTURE_TRANSLATION=NLT in env.json and rebuild.
-- Nothing else changes: both editions live in the table at once, each row
-- carries its own translation, and the build decides which is delivered.
-- Passages left as placeholders here are still delivered — as WEBBE, from the
-- rows the other seed inserted, each carrying its own credit.
`;

const nltBody = nltHeader + '\n' + nltRows(scripture) + nltFooter;

// The guardrail that matters most in this whole script: the template must
// contain no NLT text at all. Every scripture row's body must be the
// placeholder, and there must be exactly as many placeholders as rows.
const placeholderCount = (nltBody.match(/<<PASTE LICENSED NLT TEXT HERE>>/g) || []).length;
if (placeholderCount !== scripture.length + 1) {
  // +1 for the single mention inside the "HOW TO FILL THIS IN" prose.
  throw new Error(
    `NLT template placeholder count ${placeholderCount} != ${scripture.length + 1}`
  );
}
for (const p of scripture) {
  if (nltBody.includes(p.body)) {
    throw new Error(`WEBBE text leaked into the NLT template: ${p.reference}`);
  }
}

fs.writeFileSync(
  path.join(ROOT, 'supabase/seed/scripture_prompts_nlt_seed.sql.template'),
  nltBody,
  'utf8'
);

// ---------------------------------------------------------------- report ----

const byBook = {};
const byCategory = {};
for (const p of prompts) {
  byCategory[p.category] = (byCategory[p.category] || 0) + 1;
  const book =
    p.kind === 'prayer'
      ? '(prayer)'
      : p.reference.replace(/\s+\d+\s*[:.]\s*[\d,\-–\s]+$/, '').trim();
  byBook[book] = (byBook[book] || 0) + 1;
}

console.log(`prompts: ${prompts.length}  (scripture ${scripture.length}, prayers ${prayers.length})`);
console.log(`NLT template verses (ranges expanded): ${nltVerses}; combined with devotionals ${combined}`);
console.log('\ncategories:');
for (const [k, v] of Object.entries(byCategory)) console.log(`  ${k.padEnd(14)} ${v}`);
console.log(`\nbooks: ${Object.keys(byBook).filter((b) => b !== '(prayer)').length} distinct`);
const sorted = Object.entries(byBook).sort((a, b) => b[1] - a[1]);
for (const [k, v] of sorted.slice(0, 14)) {
  console.log(`  ${k.padEnd(18)} ${String(v).padStart(3)}  ${((v / prompts.length) * 100).toFixed(1)}%`);
}
