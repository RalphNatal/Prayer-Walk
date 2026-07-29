-- Members propose scripture; admins publish it.
--
-- ⚠️ This migration REPLACES AN EXISTING RLS POLICY. Read before applying.
--
-- `20260727020000_scripture_prompts.sql` gave the table two policies: everyone
-- signed in reads `is_published` rows, and admins manage everything. There was
-- no third state, so a member had nothing to contribute with. This adds one —
-- and only one: a member may propose. Nobody but an admin may publish.
--
-- The reason is not procedural. A scripture prompt is delivered *into somebody
-- else's walk*, unasked, while they are outdoors and half-attending. That is a
-- channel worth guarding: unmoderated text pushed into a stranger's prayer is
-- the failure mode this queue exists to make impossible, and it is why nothing
-- below lets a submission publish itself.
--
-- ⚖️ And a licensing reason, which is the harder one.
--
-- Tyndale permit up to 500 NLT verses without written permission. The curated
-- admin set is about fifty and sits comfortably inside that. Member submissions
-- do not have a ceiling of their own: a parish enthusiastically pasting NLT
-- passages would pass five hundred verses in a season, nobody would be counting,
-- and a manageable permission question would have become genuine infringement
-- at a scale nobody could reconstruct afterwards.
--
-- So the submission path is built so that members contribute *references and
-- their own words*. `contributor_note` is the field the form is really about.
-- Where a free-text scripture body is offered at all it is public-domain only,
-- and that is enforced here rather than asked for politely in the UI: the
-- insert policy below refuses any translation this app does not hold outright.
-- An admin may still change a translation on review, which is the one path by
-- which licensed text can enter — deliberately, by somebody who has seen the
-- verse counter.

-- ------------------------------------------------------------ the columns ---

alter table public.scripture_prompts
  add column if not exists submitted_by uuid references public.profiles(id) on delete set null,
  add column if not exists status text,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text not null default '',
  -- The member's own reflection or prayer, in their own words. Not scripture,
  -- not quoted from anywhere, and therefore not licensed from anywhere: this is
  -- the part of a submission that is unambiguously theirs to give.
  add column if not exists contributor_note text not null default '';

-- Everything already in the table was put there by an admin, through the
-- console or the seed file. It is approved by definition — backfilling it to
-- `pending` would empty the walk library into a review queue.
update public.scripture_prompts
   set status = 'approved'
 where status is null;

alter table public.scripture_prompts
  alter column status set default 'pending';
alter table public.scripture_prompts
  alter column status set not null;

alter table public.scripture_prompts
  drop constraint if exists scripture_prompts_status_check;
alter table public.scripture_prompts
  add constraint scripture_prompts_status_check
  check (status in ('pending', 'approved', 'rejected'));

-- Nothing unapproved is ever live on a walk, whatever else is true of the row.
-- The policies below say the same thing about who may read what; this says it
-- about the data, so a future admin screen cannot publish a pending row by
-- forgetting a field.
alter table public.scripture_prompts
  drop constraint if exists scripture_prompts_published_is_approved;
alter table public.scripture_prompts
  add constraint scripture_prompts_published_is_approved
  check (not is_published or status = 'approved');

create index if not exists scripture_prompts_status_idx
  on public.scripture_prompts (status, created_at desc);

create index if not exists scripture_prompts_submitted_by_idx
  on public.scripture_prompts (submitted_by);

-- --------------------------------------------------------------- policies ---

-- Published *and* approved. The old policy said only `is_published`, which was
-- sufficient when the only way into the table was an admin's own hand.
drop policy if exists "Published prompts readable by authenticated" on public.scripture_prompts;
create policy "Published prompts readable by authenticated"
  on public.scripture_prompts for select to authenticated
  using (is_published and status = 'approved');

-- A member sees what they sent, whatever became of it — including a rejection
-- and its reason. A queue that swallows submissions without saying so teaches
-- people to stop sending them.
drop policy if exists "Members read their own submissions" on public.scripture_prompts;
create policy "Members read their own submissions"
  on public.scripture_prompts for select to authenticated
  using (submitted_by = auth.uid());

-- ⚖️ The licensing guard, in the one place that cannot be skipped.
--
-- A member may insert a row that is theirs, pending, unpublished, and carries
-- no translation this app does not own outright. `WEBBE` (and `WEB`, the column
-- default from before the British edition was settled on) is public domain;
-- an empty translation is a prayer, quoting nobody. Anything else — NLT, NIV,
-- ESV, or a code this build has never heard of — is refused by the database.
--
-- This is the rule that keeps the 500-verse ceiling a question about a curated
-- list rather than about an open submissions form.
drop policy if exists "Members submit their own prompts" on public.scripture_prompts;
create policy "Members submit their own prompts"
  on public.scripture_prompts for insert to authenticated
  with check (
    submitted_by = auth.uid()
    and status = 'pending'
    and is_published = false
    and reviewed_by is null
    and reviewed_at is null
    and upper(btrim(coalesce(translation, ''))) in ('', 'WEB', 'WEBBE')
  );

-- Withdrawing something you have not had answered yet. Deliberately narrow:
-- once a submission is approved it belongs to the library and to the walks it
-- is being delivered on, and taking it back out is an admin's decision.
drop policy if exists "Members withdraw their own pending submissions" on public.scripture_prompts;
create policy "Members withdraw their own pending submissions"
  on public.scripture_prompts for delete to authenticated
  using (submitted_by = auth.uid() and status = 'pending');

-- Note what is *not* here: no member UPDATE policy. There is no path by which a
-- member can move their own row to `approved`, set `is_published`, or change a
-- translation after the fact. "Admins manage prompts" from the original
-- migration is still the only policy that can, and it is unchanged.

-- Suspension, on the same terms as everywhere else: a suspended member may read
-- and may report, and may not add to what other people are given on a walk.
drop policy if exists "Suspended members do not submit prompts" on public.scripture_prompts;
create policy "Suspended members do not submit prompts"
  on public.scripture_prompts as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

-- ---------------------------------------------------- review, timestamped ---
--
-- Who decided, and when. Set by a trigger rather than by the console, so the
-- record exists even if a future screen forgets to write it — an approval with
-- nobody's name on it is the shape a moderation trail fails in.
create or replace function public.pw_stamp_prompt_review()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('approved', 'rejected') then
    new.reviewed_by := coalesce(new.reviewed_by, auth.uid());
    new.reviewed_at := coalesce(new.reviewed_at, now());
  end if;

  -- Sending something back to the queue clears the decision with it.
  if new.status = 'pending' and old.status is distinct from 'pending' then
    new.reviewed_by := null;
    new.reviewed_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists scripture_prompts_stamp_review on public.scripture_prompts;
create trigger scripture_prompts_stamp_review
  before update on public.scripture_prompts
  for each row execute function public.pw_stamp_prompt_review();

-- --------------------------------------------------- C3 · the contributor ---
--
-- A prompt keeps the name of whoever proposed it, and the app renders it beside
-- the verse. Provenance is not decoration here: it is half of what makes a
-- member-contributed library feel like a parish rather than a content feed, and
-- the other half is the translation mark that the same card already carries.
--
-- The app reads it as a PostgREST embed on `submitted_by`, which keeps the
-- library one request. The embed has to name its constraint —
-- `scripture_prompts_submitted_by_fkey` — because this table now reaches
-- `profiles` twice and PostgREST cannot tell the contributor from the reviewer
-- without being told. The two constraints are named here so that the app's
-- select string has something stable to point at.
alter table public.scripture_prompts
  drop constraint if exists scripture_prompts_submitted_by_fkey;
alter table public.scripture_prompts
  add constraint scripture_prompts_submitted_by_fkey
  foreign key (submitted_by) references public.profiles(id) on delete set null;

alter table public.scripture_prompts
  drop constraint if exists scripture_prompts_reviewed_by_fkey;
alter table public.scripture_prompts
  add constraint scripture_prompts_reviewed_by_fkey
  foreign key (reviewed_by) references public.profiles(id) on delete set null;
