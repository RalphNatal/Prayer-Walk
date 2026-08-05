// Checks every seeded WEBBE passage against an authoritative public-domain
// source, and reports mismatches by reference. It never rewrites anything —
// the seed's own header already says why: the passages were selected and
// transcribed for this library rather than pulled programmatically, and
// "public domain" means nobody is owed a fee, not that a transcription error
// is acceptable in somebody's prayer. This script is the diff; a mismatch is
// the maintainer's to fix against the source, never this script's.
//
//   cd tool/scripture
//   npm install
//   node verify.js
//
// Source: https://eBible.org/Scriptures/eng-webbe_vpl.zip — eBible's own
// verse-per-line plain-text export of the World English Bible, British
// Edition, linked from https://ebible.org/find/details.php?id=eng-webbe (the
// same page supabase/seed/scripture_prompts_seed.sql's own header points at).
//
// Honesty about this script's own limits: the exact line format inside that
// zip was not confirmed against the live file before this was written (see
// the project's build-verification notes for why). It prints the first few
// raw lines before parsing, and refuses to guess silently if neither of the
// two formats it knows how to read matches — see `detectFormat` below. If
// that happens, paste the printed lines back for a quick follow-up fix; it is
// not a sign anything is wrong with the seeded text itself.
//
// Only `kind: 'scripture', translation: 'WEBBE'` rows are checked. Prayers
// (`kind: 'prayer'`) quote no translation and are skipped, counted but not
// verified — they are ancient formulas or written for this app, not sourced
// from WEBBE.

const fs = require('fs');
const path = require('path');
const AdmZip = require('adm-zip');

const SOURCE_URL = 'https://eBible.org/Scriptures/eng-webbe_vpl.zip';

const CATEGORIES = [
  ['morningLight', require('./morning.js')],
  ['gratitude', require('./gratitude.js')],
  ['intercession', require('./intercession.js')],
  ['lament', require('./lament.js')],
  ['stillness', require('./stillness.js')],
  ['scriptureWalk', require('./walk.js')],
];

// ---------------------------------------------------------- book mapping ----
//
// Standard USFM three-letter codes, in canon order. eBible's VPL export may
// key lines by this code or by the full English name — `detectFormat` below
// works out which, and this table serves either direction since English name
// is always the left-hand key this app already has.
const BOOK_CODES = {
  Genesis: 'GEN', Exodus: 'EXO', Leviticus: 'LEV', Numbers: 'NUM',
  Deuteronomy: 'DEU', Joshua: 'JOS', Judges: 'JDG', Ruth: 'RUT',
  '1 Samuel': '1SA', '2 Samuel': '2SA', '1 Kings': '1KI', '2 Kings': '2KI',
  '1 Chronicles': '1CH', '2 Chronicles': '2CH', Ezra: 'EZR', Nehemiah: 'NEH',
  Esther: 'EST', Job: 'JOB', Psalm: 'PSA', Psalms: 'PSA', Proverbs: 'PRO',
  Ecclesiastes: 'ECC', 'Song of Songs': 'SNG', 'Song of Solomon': 'SNG',
  Isaiah: 'ISA', Jeremiah: 'JER', Lamentations: 'LAM', Ezekiel: 'EZK',
  Daniel: 'DAN', Hosea: 'HOS', Joel: 'JOL', Amos: 'AMO', Obadiah: 'OBA',
  Jonah: 'JON', Micah: 'MIC', Nahum: 'NAM', Habakkuk: 'HAB',
  Zephaniah: 'ZEP', Haggai: 'HAG', Zechariah: 'ZEC', Malachi: 'MAL',
  Matthew: 'MAT', Mark: 'MRK', Luke: 'LUK', John: 'JHN', Acts: 'ACT',
  Romans: 'ROM', '1 Corinthians': '1CO', '2 Corinthians': '2CO',
  Galatians: 'GAL', Ephesians: 'EPH', Philippians: 'PHP', Colossians: 'COL',
  '1 Thessalonians': '1TH', '2 Thessalonians': '2TH', '1 Timothy': '1TI',
  '2 Timothy': '2TI', Titus: 'TIT', Philemon: 'PHM', Hebrews: 'HEB',
  James: 'JAS', '1 Peter': '1PE', '2 Peter': '2PE', '1 John': '1JN',
  '2 John': '2JN', '3 John': '3JN', Jude: 'JUD', Revelation: 'REV',
};

// -------------------------------------------------------- app's own list ----
//
// Rebuilt independently from generate.js rather than importing it: this
// script must never touch or depend on the generator's own correctness, only
// on the same raw theme files it also reads.
function loadPrompts() {
  const prompts = [];
  for (const [category, rows] of CATEGORIES) {
    for (const [rawRef, body] of rows) {
      if (rawRef.startsWith('PRAYER:')) {
        prompts.push({ reference: rawRef.slice('PRAYER:'.length), body, kind: 'prayer', category });
      } else {
        prompts.push({ reference: rawRef, body, kind: 'scripture', category });
      }
    }
  }
  return prompts;
}

// A reference like "Lamentations 3:22-23" or "Psalm 5:3" into a book,
// chapter, and the list of verse numbers it covers. Comma lists
// ("Psalm 1:1,3") are supported even though none exist in the library today,
// since generate.js's own verse counter already anticipates them. Returns
// null for a shape this doesn't recognise — the caller reports that as
// unmapped rather than guessing.
function parseReference(ref) {
  const m = ref.match(/^(.+?)\s+(\d+):([\d,\-]+)$/);
  if (!m) return null;
  const [, book, chapterStr, versePart] = m;
  const verses = [];
  for (const piece of versePart.split(',')) {
    const range = piece.match(/^(\d+)-(\d+)$/);
    if (range) {
      for (let v = Number(range[1]); v <= Number(range[2]); v++) verses.push(v);
    } else {
      verses.push(Number(piece));
    }
  }
  return { book: book.trim(), chapter: Number(chapterStr), verses };
}

// -------------------------------------------------------- text comparison ---
//
// Not byte-exact by design: the app's bodies are plain prose with no verse
// numbers, while the source is naturally per-verse. This normalises both
// sides enough to compare the words themselves — smart quotes, whitespace,
// case — while leaving the raw text intact in the mismatch report so a real
// wording difference is still visible to a human, not hidden by the
// normalisation.
function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/\s+/g, ' ')
    .trim();
}

// -------------------------------------------------------------- fetching ----

async function fetchSource() {
  console.log(`Fetching ${SOURCE_URL} ...`);
  const response = await fetch(SOURCE_URL);
  if (!response.ok) {
    throw new Error(`download failed: HTTP ${response.status}`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  const zip = new AdmZip(buffer);
  const entries = zip.getEntries().filter((e) => !e.isDirectory);
  const txtEntry =
    entries.find((e) => /vpl/i.test(e.entryName) && e.entryName.endsWith('.txt')) ||
    entries.find((e) => e.entryName.endsWith('.txt'));
  if (!txtEntry) {
    throw new Error(
      `no .txt entry found in the zip — entries were: ${entries.map((e) => e.entryName).join(', ')}`
    );
  }
  console.log(`Reading ${txtEntry.entryName} (${txtEntry.header.size} bytes)`);
  return txtEntry.getData().toString('utf8');
}

// One VPL line is expected to be a reference and the verse text, separated by
// whitespace/a tab. Two shapes are known to eBible exports; this tries both
// against the first non-empty lines and picks whichever parses cleanly rather
// than assuming.
function detectFormat(lines) {
  const sample = lines.slice(0, 20).filter((l) => l.trim());
  console.log('First few source lines, for a sanity check:');
  for (const line of sample.slice(0, 5)) console.log('  ' + JSON.stringify(line));

  const codeShape = /^([1-3]?[A-Z]{2,3})\s+(\d+):(\d+)\s+(.+)$/;
  const nameShape = /^([1-3]?\s?[A-Za-z][A-Za-z .]*?)\s+(\d+):(\d+)\s+(.+)$/;

  const codeHits = sample.filter((l) => codeShape.test(l)).length;
  const nameHits = sample.filter((l) => nameShape.test(l)).length;

  if (codeHits >= sample.length * 0.8) return { shape: codeShape, byCode: true };
  if (nameHits >= sample.length * 0.8) return { shape: nameShape, byCode: false };
  return null;
}

function buildLookup(text) {
  const lines = text.split(/\r?\n/);
  const format = detectFormat(lines);
  if (!format) {
    console.error(
      '\nCould not recognise the source file\'s line format from either shape ' +
        'this script knows. Paste a few raw lines (printed above) back for a ' +
        'quick fix to `detectFormat`/`buildLookup` in this file — this is not ' +
        'a problem with the seeded scripture text.'
    );
    process.exit(1);
  }

  const lookup = new Map();
  let matched = 0;
  for (const line of lines) {
    const m = line.match(format.shape);
    if (!m) continue;
    matched++;
    const [, bookKey, chapter, verse, verseText] = m;
    const code = format.byCode
      ? bookKey.toUpperCase()
      : BOOK_CODES[bookKey.trim()] || bookKey.trim().toUpperCase();
    lookup.set(`${code}|${chapter}|${verse}`, verseText.trim());
  }
  console.log(`Parsed ${matched} verse lines from the source (${lookup.size} unique keys).\n`);
  return lookup;
}

// ------------------------------------------------------------------ main ----

async function main() {
  const prompts = loadPrompts();
  const scripture = prompts.filter((p) => p.kind === 'scripture');
  const prayers = prompts.filter((p) => p.kind === 'prayer');

  const sourceText = await fetchSource();
  const lookup = buildLookup(sourceText);

  let matches = 0;
  let mismatches = 0;
  let unmapped = 0;

  for (const p of scripture) {
    const parsed = parseReference(p.reference);
    if (!parsed) {
      unmapped++;
      console.log(`UNMAPPED  ${p.reference}  — reference shape not recognised`);
      continue;
    }
    const code = BOOK_CODES[parsed.book];
    if (!code) {
      unmapped++;
      console.log(`UNMAPPED  ${p.reference}  — book "${parsed.book}" has no USFM code in this script's table`);
      continue;
    }

    const verseTexts = [];
    let missing = null;
    for (const v of parsed.verses) {
      const key = `${code}|${parsed.chapter}|${v}`;
      const text = lookup.get(key);
      if (text === undefined) {
        missing = key;
        break;
      }
      verseTexts.push(text);
    }
    if (missing) {
      unmapped++;
      console.log(`UNMAPPED  ${p.reference}  — source has no verse at ${missing}`);
      continue;
    }

    const sourceJoined = verseTexts.join(' ');
    if (normalize(sourceJoined) === normalize(p.body)) {
      matches++;
    } else {
      mismatches++;
      console.log(`\nMISMATCH  ${p.reference}`);
      console.log(`  app:    ${p.body}`);
      console.log(`  source: ${sourceJoined}`);
    }
  }

  console.log('\n' + '='.repeat(72));
  console.log(
    `${scripture.length} scripture passages checked: ${matches} match, ` +
      `${mismatches} mismatch, ${unmapped} unmapped/unresolved.`
  );
  console.log(`${prayers.length} prayers skipped (not sourced from WEBBE).`);
  console.log('='.repeat(72));

  if (mismatches > 0 || unmapped > 0) {
    console.error(
      '\nDo not rewrite any of the above from memory. Correct the transcribed ' +
        'text in the relevant tool/scripture/*.js theme file against the ' +
        'source referenced at the top of this script, then re-run ' +
        '`node generate.js` and this script again.'
    );
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(`\nverify.js failed: ${error.message}`);
  console.error(
    'If this is a network/download failure, download ' +
      `${SOURCE_URL} by hand and adjust fetchSource() to read the local file ` +
      'instead — the rest of the script does not care where the text came from.'
  );
  process.exitCode = 1;
});
