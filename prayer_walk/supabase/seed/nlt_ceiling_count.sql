-- ===========================================================================
-- THE CEILING COUNTER — read-only. Run this before and after every NLT fill.
-- ===========================================================================
--
-- Tyndale allows the New Living Translation to be quoted without express
-- written permission only within three limits, all of which must hold:
--
--   * up to 500 verses, and
--   * not more than 25% of the work in which they are quoted, and
--   * no complete book of the Bible.
--
-- This query answers the first one. The other two it does not check at all —
-- see the notes at the foot of this file.
--
-- Requests beyond the limits go to permission@tyndale.com.
--
-- Safe to run at any time: it selects and nothing else. It is the same
-- arithmetic the admin Scripture screen shows in-app (`_LicensedVerseCount` →
-- `approximateVerseCount`), so the two should agree; if they disagree, the app
-- is reading a stale or filtered library and the number here is the one to
-- trust.
--
-- Counted across BOTH tables. Tyndale's limit is on the work, not on one of its
-- lists — a verse quoted in a devotional spends the same allowance as one
-- delivered on a walk.
-- ---------------------------------------------------------------------------

with quoted as (
  select reference
  from public.scripture_prompts
  where translation = 'NLT'
  union all
  select scripture_ref
  from public.devotionals
  where translation = 'NLT'
),
expanded as (
  select
    reference,
    case
      -- 'Psalm 121:1-2' → 2. Only a trailing same-chapter range expands.
      when reference ~ ':\s*\d+\s*-\s*\d+\s*$'
        then (regexp_replace(reference, '^.*:\s*\d+\s*-\s*(\d+)\s*$', '\1'))::int
           - (regexp_replace(reference, '^.*:\s*(\d+)\s*-\s*\d+\s*$', '\1'))::int
           + 1
      else 1
    end as verses
  from quoted
)
select
  count(*)                          as passages,
  coalesce(sum(verses), 0)          as approx_verses,
  500                               as ceiling,
  500 - coalesce(sum(verses), 0)    as headroom,
  round(100.0 * coalesce(sum(verses), 0) / 500, 1) as percent_of_ceiling
from expanded;

-- ---------------------------------------------------------------------------
-- WHAT THIS NUMBER IS NOT
--
--  * `approx_verses` is a FLOOR. It expands `1 Thessalonians 5:16-18` into
--    three, but reads `Psalm 1:1,3` (a list) and `Psalm 22:31-23:1` (crossing a
--    chapter) as one apiece. It therefore under-counts, never over-counts.
--    Count by hand before going anywhere near 500.
--
--  * It does not check the 25% condition, which is about the proportion of the
--    finished product rather than about this table.
--
--  * It does not check the "no complete book" condition at all. A short book —
--    Jude, Philemon, 2 or 3 John, Obadiah — could be quoted whole while this
--    query reports comfortable headroom. To look for that:
--
--      select
--        regexp_replace(reference, '\s+\d+:.*$', '') as book,
--        count(*) as passages
--      from public.scripture_prompts
--      where translation = 'NLT'
--      group by 1
--      order by 2 desc;
--
--    then compare any short book's count against its actual verse total.
--
-- WHICH ROWS ARE COUNTED
--
-- Every NLT row in either table, published or not. Draft rows count: they are
-- licensed text held in the product, and the limit is on quotation rather than
-- on delivery. Placeholder rows do not exist to be counted — the seed template
-- skips anything still reading '<<PASTE…' rather than inserting it.
--
-- Rows in any other translation are ignored. WEBBE is public domain: no fee, no
-- permission, no ceiling, and it can grow without limit.
-- ---------------------------------------------------------------------------
