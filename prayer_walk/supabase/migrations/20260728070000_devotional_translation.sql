-- `translation` on devotionals — the provenance of a quoted passage.
--
-- `scripture_prompts` has carried this since the table was created; devotionals
-- quote scripture too (`scripture_ref` / `scripture_text`) and had nowhere to
-- record which edition the words came from. That was survivable while every
-- passage was public-domain WEBBE and nothing was owed to anybody. It is not
-- survivable for a licensed translation, where the credit line and the
-- per-quotation mark are conditions of use — and where the app has to know,
-- per row, what it owes.
--
-- Nullable rather than `not null default ''`, so the table keeps the
-- distinction the app relies on: null is "no passage, or an edition nobody has
-- named yet"; a value is a claim about provenance an editor actually made.
--
-- Safe to re-run.

alter table public.devotionals
  add column if not exists translation text;

comment on column public.devotionals.translation is
  'Edition scripture_text was quoted from (e.g. WEBBE, NLT). Null when the '
  'devotional quotes nothing. A licensed edition here obliges the app to show '
  'that translation''s credit line and per-quotation mark.';

-- Everything that existed before this migration is the WEBBE seed set or was
-- written from the console under a console that only offered WEBBE. Rows that
-- quote nothing are left null rather than labelled, because there is nothing
-- there to attribute.
update public.devotionals
   set translation = 'WEBBE'
 where translation is null
   and coalesce(trim(scripture_text), '') <> '';
