-- Group scripture: a church group's admins publish prompts that only that
-- group's members receive on a walk, alongside the global library.
--
-- ⚠️ This migration NARROWS TWO EXISTING RLS POLICIES on `scripture_prompts`.
-- Read before applying.
--
--   * "Published prompts readable by authenticated" gains `group_id is null`.
--     Without it, every group's published scripture would be readable by every
--     signed-in member — the existing policy only asks `is_published and
--     status = 'approved'`, which a group's rows also satisfy.
--   * "Members submit their own prompts" gains `group_id is null`, so the
--     member submissions path cannot be used to drop a pending row into a
--     group the member does not run.
--
-- Both are strictly narrower than before; nothing that was readable or
-- writable for a global row changes. Group access is granted by NEW policies
-- alongside them rather than by loosening either one. Against a 1.0 client
-- this is invisible: there are no group rows until 1.1 writes some.
--
-- ⚖️ LICENSING
-- -------------
-- The reasoning in 20260728110000_scripture_submissions.sql applies here with
-- more force, not less. Tyndale's 500-verse NLT ceiling is a limit on CALLED
-- Presentations' use across the whole app; a group admin pasting NLT into
-- their group's feed spends that allowance without anybody counting, and a
-- group admin pasting the ESV or the NIV has no allowance to spend at all.
--
-- So group scripture is public domain or a prayer, and that is a CHECK
-- CONSTRAINT rather than a policy: it binds every writer, app admins
-- included, so no console edit can turn a group's verse into a licensed one.
-- The group admin also confirms, in the app, that they have the right to
-- publish what they post — who confirmed and when is stored on the row. The
-- confirmation is for the text around the verse (their own prayer, their own
-- words); the constraint is what covers the verse itself.

-- ------------------------------------------------------------- columns ---

alter table public.scripture_prompts
  add column if not exists group_id uuid
    references public.church_groups(id) on delete cascade,
  -- Which group admin posted it. Not `submitted_by`: that column means "a
  -- member proposed this for review" and drives the submissions queue, which
  -- a group's own posts never pass through.
  add column if not exists published_by uuid
    references public.profiles(id) on delete set null,
  add column if not exists rights_attested_by uuid
    references public.profiles(id) on delete set null,
  add column if not exists rights_attested_at timestamptz;

create index if not exists scripture_prompts_group_idx
  on public.scripture_prompts (group_id, is_published);

-- The rule a group's row always satisfies, whoever wrote it.
alter table public.scripture_prompts
  drop constraint if exists scripture_prompts_group_rows_public_domain;
alter table public.scripture_prompts
  add constraint scripture_prompts_group_rows_public_domain
  check (
    group_id is null
    or (
      rights_attested_at is not null
      and submitted_by is null
      and upper(btrim(coalesce(translation, ''))) in ('', 'WEB', 'WEBBE')
    )
  );

-- --------------------------------------------- the two narrowed policies ---

drop policy if exists "Published prompts readable by authenticated" on public.scripture_prompts;
create policy "Published prompts readable by authenticated"
  on public.scripture_prompts for select to authenticated
  using (group_id is null and is_published and status = 'approved');

-- From 20260728110000, unchanged except for the last line.
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
    and group_id is null
  );

-- ------------------------------------------------- the group's own rows ---

-- A group's published prompts, to that group's active members. Pending and
-- banned members are not members for this purpose.
drop policy if exists "Group members read their group's prompts" on public.scripture_prompts;
create policy "Group members read their group's prompts"
  on public.scripture_prompts for select to authenticated
  using (
    group_id is not null
    and is_published
    and status = 'approved'
    and public.is_group_member(group_id)
  );

-- Drafts included, for the group's admins.
drop policy if exists "Group admins read their group's prompts" on public.scripture_prompts;
create policy "Group admins read their group's prompts"
  on public.scripture_prompts for select to authenticated
  using (group_id is not null and public.is_group_admin(group_id));

-- Posting. Approved on arrival — the group admin is the reviewer for their own
-- group, and the global queue is not theirs to fill — and attested by the
-- person posting, as themselves.
drop policy if exists "Group admins publish to their group" on public.scripture_prompts;
create policy "Group admins publish to their group"
  on public.scripture_prompts for insert to authenticated
  with check (
    group_id is not null
    and public.is_group_admin(group_id)
    and published_by = auth.uid()
    and rights_attested_by = auth.uid()
    and submitted_by is null
    and status = 'approved'
    and reviewed_by is null
  );

-- Editing. Whoever changes the *text* re-attests — enforced by the trigger
-- below, which can see what changed; a policy cannot. Publishing and
-- unpublishing leave the original attestation exactly as it was.
drop policy if exists "Group admins edit their group's prompts" on public.scripture_prompts;
create policy "Group admins edit their group's prompts"
  on public.scripture_prompts for update to authenticated
  using (group_id is not null and public.is_group_admin(group_id))
  with check (
    group_id is not null
    and public.is_group_admin(group_id)
    and submitted_by is null
    and status = 'approved'
  );

drop policy if exists "Group admins delete their group's prompts" on public.scripture_prompts;
create policy "Group admins delete their group's prompts"
  on public.scripture_prompts for delete to authenticated
  using (group_id is not null and public.is_group_admin(group_id));

-- "Admins manage prompts" (20260727020000) is untouched and still covers every
-- row, group rows included. That is the oversight half of the decision: an app
-- admin can unpublish a group's verse in answer to a report. The constraint
-- above still holds against them.

-- ------------------------------------------- the moment of attestation ---
--
-- Two rules a policy cannot express, because both depend on what changed:
--
--   * New text — an insert, or an edit to the body, reference or translation —
--     is attested by the person writing it, as themselves, now. "Now" is the
--     server's clock, the only one that cannot be set to suit.
--   * Anything else (publishing, unpublishing, re-sorting) leaves the existing
--     attestation exactly as it was. Unpublishing a verse is not a claim to
--     have the right to it, and the record should not say it was.
--
-- Applies to app admins too: an app admin rewriting a group's verse is the
-- person vouching for the new text.
create or replace function public.pw_stamp_group_prompt()
returns trigger
language plpgsql
as $$
declare
  new_text boolean;
begin
  if new.group_id is null then
    return new;
  end if;
  if current_user in ('service_role', 'postgres') then
    new.rights_attested_at := coalesce(new.rights_attested_at, now());
    return new;
  end if;

  new_text := tg_op = 'INSERT'
    or new.body        is distinct from old.body
    or new.reference   is distinct from old.reference
    or new.translation is distinct from old.translation;

  if new_text then
    if new.rights_attested_by is distinct from auth.uid() then
      raise exception
        'Confirm you have the right to publish this text before saving it.'
        using errcode = '42501';
    end if;
    new.rights_attested_at := now();
  else
    -- Cleared is allowed: that is `on delete set null` when the person who
    -- attested deletes their account. Reassigned is not.
    if new.rights_attested_by is not null then
      new.rights_attested_by := old.rights_attested_by;
    end if;
    new.rights_attested_at := old.rights_attested_at;
  end if;
  return new;
end;
$$;

drop trigger if exists scripture_prompts_stamp_group on public.scripture_prompts;
create trigger scripture_prompts_stamp_group
  before insert or update on public.scripture_prompts
  for each row execute function public.pw_stamp_group_prompt();

-- ---------------------------------------------------------------- delivery ---
--
-- What a walk draws from: the global library plus every group the walker is
-- an active member of. One round trip, as the table select it replaces was.
--
-- A function rather than leaning on the policies above, because the policies
-- are a superset for one kind of caller: "Admins manage prompts" lets an app
-- admin read every group's rows, and a walk should never hand an admin the
-- scripture of churches they do not belong to. The predicate here says what a
-- walk wants; RLS still decides what the caller may see at all.
--
-- The contributor comes back as the same `{full_name}` object the table select
-- embedded, and the group as `{id, name}`, so the app's one row mapper reads
-- the network, the cache and the bundled asset alike.
create or replace function public.walk_scripture_library()
returns table (
  id               uuid,
  reference        text,
  body             text,
  translation      text,
  kind             text,
  category         text,
  sort_order       integer,
  is_published     boolean,
  status           text,
  submitted_by     uuid,
  contributor_note text,
  rejection_reason text,
  reviewed_at      timestamptz,
  created_at       timestamptz,
  group_id         uuid,
  contributor      jsonb,
  church_group     jsonb
)
language sql
stable
as $$
  select
    sp.id,
    sp.reference,
    sp.body,
    sp.translation,
    sp.kind,
    sp.category,
    sp.sort_order,
    sp.is_published,
    sp.status,
    sp.submitted_by,
    sp.contributor_note,
    sp.rejection_reason,
    sp.reviewed_at,
    sp.created_at,
    sp.group_id,
    case when c.id is null then null
         else jsonb_build_object('full_name', c.full_name) end,
    case when g.id is null then null
         else jsonb_build_object('id', g.id, 'name', g.name) end
  from public.scripture_prompts sp
  left join public.profiles c on c.id = sp.submitted_by
  left join public.church_groups g
         on g.id = sp.group_id and g.deleted_at is null
  where sp.is_published
    and sp.status = 'approved'
    and (
      sp.group_id is null
      or (g.id is not null and public.is_group_member(sp.group_id))
    )
  order by sp.group_id nulls first, sp.sort_order, sp.created_at;
$$;

grant execute on function public.walk_scripture_library() to authenticated;

comment on column public.scripture_prompts.group_id is
  'Null for the global library. Set for a church group''s own prompts, which '
  'only that group''s active members receive. Always public domain or a prayer '
  '(scripture_prompts_group_rows_public_domain).';
comment on column public.scripture_prompts.rights_attested_by is
  'For a group''s prompt: the group admin who confirmed they may publish it.';
