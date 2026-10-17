-- Church groups: a church has a group, members join it, and its admins look
-- after it.
--
-- Additive. Three new tables, a Storage bucket, and one widened check
-- constraint on `moderation_reports`. Nothing a 1.0 client reads changes shape,
-- so this is safe to apply while 1.0 is live.
--
-- TWO KINDS OF ADMIN
-- ------------------
-- `profiles.role = 'admin'` is CALLED Presentations running the app: the
-- console, the global scripture library, the moderation queue. A *group*
-- admin is a member who looks after one church's group, and nothing else.
-- Nothing in this file lets a group admin reach the console, the global
-- library, or anybody's data outside their own group, and no function here
-- treats the two as interchangeable. App admins can read and remove any group,
-- because group content is user-generated and someone has to be able to act
-- on a report about it; that oversight is granted explicitly below, policy by
-- policy, rather than inherited.
--
-- WHY THE MEMBERSHIP HELPERS ARE `security definer`
-- -------------------------------------------------
-- `is_admin()` is security invoker, and its comment explains why that is safe:
-- the profiles SELECT policy does not read `profiles`, so asking "is this an
-- admin" from inside a profiles policy terminates in one step.
--
-- The same is not true here. "Members see their own group's roster" is a
-- policy on `church_group_members` that has to ask "is the caller a member of
-- this group" — which is a read of `church_group_members`, which consults the
-- policy, which asks again. An invoker helper recurses (42P17) the first time
-- anyone opens a roster. That is exactly the trap the `is_admin()` comment
-- warns about, and `pw_is_admin()` in 20260728080000 is the precedent for the
-- way out: run as the table owner, for whom RLS does not apply, and return
-- nothing but a boolean.
--
-- So `is_group_member()` and `is_group_admin()` are definer functions with a
-- pinned `search_path`, and they are written so the extra privilege cannot be
-- used to learn anything: they answer about the caller, or about another
-- member only to somebody who could already read that member's row (a fellow
-- member, or an app admin). The same reasoning `pw_is_blocked` gives for
-- taking one parameter, applied to a function the brief asked to take two.
--
-- ⚠️ As with the other definer functions in this schema, these must be owned
-- by the role that owns the tables (apply as `postgres` in the SQL editor).
-- Owned by anyone else, they run under the caller's own policies and quietly
-- answer false.

-- ---------------------------------------------------------------- tables ---

create table if not exists public.church_groups (
  id              uuid primary key default gen_random_uuid(),
  name            text not null
                    check (char_length(btrim(name)) between 3 and 80),
  -- Generated from the name on insert and never changed afterwards, so a
  -- shared link keeps working when a group renames itself.
  slug            text not null unique
                    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
                           and char_length(slug) <= 72),
  description     text not null default ''
                    check (char_length(description) <= 600),
  avatar_url      text,
  cover_url       text,
  -- Helps people find their own church among several of the same name.
  city            text not null default ''
                    check (char_length(city) <= 80),
  -- False = reachable by invite code only. Not secret from its own members,
  -- and not listed anywhere else.
  is_discoverable boolean not null default true,
  join_policy     text not null default 'open'
                    check (join_policy in ('open', 'request')),
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  -- Soft delete. Set only by the succession rule below, when the last member
  -- of a group leaves or deletes their account. A group an admin removes on
  -- purpose is hard-deleted and takes its rows with it.
  deleted_at      timestamptz
);

create table if not exists public.church_group_members (
  group_id  uuid not null references public.church_groups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null default 'member' check (role in ('member', 'admin')),
  status    text not null default 'active'
              check (status in ('active', 'pending', 'banned')),
  -- Set by the server, never by the client: the succession rule promotes the
  -- longest-tenured member, and a backdated `joined_at` would be a way to
  -- queue-jump into an admin role.
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- "Which groups am I in" — the hottest read once this ships.
create index if not exists church_group_members_user_idx
  on public.church_group_members (user_id);

-- Rosters, counts and the "is there an admin left" question.
create index if not exists church_group_members_group_status_idx
  on public.church_group_members (group_id, status, role);

-- Prefix search on the name, the same trade `search_members` makes.
create index if not exists church_groups_name_prefix_idx
  on public.church_groups (lower(name) text_pattern_ops);

-- The invite code for a group, in a table of its own so it can be readable by
-- that group's admins and nobody else. A column on `church_groups` would be
-- readable by everybody who can read the group — which, for a discoverable
-- one, is everybody.
create table if not exists public.church_group_invites (
  group_id   uuid primary key references public.church_groups(id) on delete cascade,
  code       text not null unique,
  rotated_at timestamptz not null default now()
);

alter table public.church_groups        enable row level security;
alter table public.church_group_members enable row level security;
alter table public.church_group_invites enable row level security;

-- ------------------------------------------------------------- helpers ---

-- The caller's own standing in a group: 'active', 'pending', 'banned', or null.
-- Definer so the church_groups SELECT policy can ask it without reading
-- church_group_members under that table's own policy.
create or replace function public.pw_my_group_status(gid uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.status
    from public.church_group_members m
   where m.group_id = gid and m.user_id = auth.uid();
$$;

grant execute on function public.pw_my_group_status(uuid) to authenticated;

-- Is `uid` an active member of `gid`? Answers only about the caller, or to a
-- caller entitled to read that membership anyway — see the header.
create or replace function public.is_group_member(
  gid uuid, uid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Coalesced: a security helper answers true or false, never null. A null
  -- reads as "no" inside a policy but as "not refused" under `if not …`.
  select coalesce(
     auth.uid() is not null
     and exists (
       select 1 from public.church_group_members m
        where m.group_id = gid and m.user_id = uid and m.status = 'active'
     )
     and (
       uid = auth.uid()
       or public.pw_my_group_status(gid) = 'active'
       or public.pw_is_admin()
     ),
     false);
$$;

-- Is `uid` an active admin of `gid`? Same disclosure rule.
create or replace function public.is_group_admin(
  gid uuid, uid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Coalesced: a security helper answers true or false, never null. A null
  -- reads as "no" inside a policy but as "not refused" under `if not …`.
  select coalesce(
     auth.uid() is not null
     and exists (
       select 1 from public.church_group_members m
        where m.group_id = gid and m.user_id = uid
          and m.role = 'admin' and m.status = 'active'
     )
     and (
       uid = auth.uid()
       or public.pw_my_group_status(gid) = 'active'
       or public.pw_is_admin()
     ),
     false);
$$;

grant execute on function public.is_group_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_admin(uuid, uuid) to authenticated;

-- What a self-join into `gid` must look like: 'active' for an open group,
-- 'pending' for one that asks first, null for one that cannot be joined this
-- way (removed, or reachable by invite code only).
--
-- This is the server reading the group's policy, which is the point: the
-- client never decides whether its own membership is active.
create or replace function public.pw_group_join_status(gid uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case g.join_policy when 'open' then 'active' else 'pending' end
    from public.church_groups g
   where g.id = gid and g.deleted_at is null and g.is_discoverable;
$$;

grant execute on function public.pw_group_join_status(uuid) to authenticated;

-- Whether the caller may see `gid` at all — the church_groups SELECT rule in
-- function form, for the definer reads below that cannot lean on RLS.
create or replace function public.pw_can_see_group(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.church_groups g
     where g.id = gid
       and (
         (g.deleted_at is null
          and (g.is_discoverable
               or public.pw_my_group_status(g.id) in ('active', 'pending')))
         or public.pw_is_admin()
       )
  );
$$;

grant execute on function public.pw_can_see_group(uuid) to authenticated;

-- Active members, for a group the caller may see; null otherwise. A count is
-- the one thing about a roster a non-member is told.
create or replace function public.pw_group_member_count(gid uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when public.pw_can_see_group(gid) then (
    select count(*)::int from public.church_group_members m
     where m.group_id = gid and m.status = 'active'
  ) end;
$$;

grant execute on function public.pw_group_member_count(uuid) to authenticated;

-- A URL-safe slug, unique across every group including ones the caller cannot
-- see — which is why it is definer: an invoker check would miss a hidden
-- group's slug and fail the insert with a 23505 nobody could explain.
create or replace function public.pw_church_group_slug(group_name text, gid uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  base text;
begin
  base := regexp_replace(lower(coalesce(group_name, '')), '[^a-z0-9]+', '-', 'g');
  base := btrim(left(btrim(base, '-'), 60), '-');
  if base = '' then
    base := 'church';
  end if;
  if exists (select 1 from public.church_groups g where g.slug = base) then
    return base || '-' || left(replace(gid::text, '-', ''), 8);
  end if;
  return base;
end;
$$;

-- Twelve hex characters from `gen_random_uuid()` — the strong generator, not
-- `random()` — skipping the uuid's fixed version nibble. 48 bits is beyond
-- guessing through an RPC, and short enough to read aloud after Mass.
create or replace function public.pw_new_invite_code()
returns text
language sql
volatile
as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
$$;

-- --------------------------------------------------- church_groups guards ---

-- Defaults the client does not get to choose, and the columns that never move.
create or replace function public.pw_guard_church_group()
returns trigger
language plpgsql
as $$
declare
  privileged boolean := current_user in ('service_role', 'postgres');
begin
  if tg_op = 'INSERT' then
    new.slug := public.pw_church_group_slug(new.name, new.id);
    if not privileged then
      new.created_by := auth.uid();
      new.created_at := now();
      new.deleted_at := null;
    end if;
    return new;
  end if;

  -- The founder may be *cleared* — that is `on delete set null` firing when
  -- they delete their account, and refusing it would make account deletion
  -- fail for anyone who ever started a group — but never reassigned.
  if not privileged
     and (new.slug is distinct from old.slug
          or (new.created_by is distinct from old.created_by
              and new.created_by is not null)
          or new.created_at is distinct from old.created_at)
  then
    raise exception 'A group''s link, founder and start date do not change.'
      using errcode = '42501';
  end if;

  if new.deleted_at is distinct from old.deleted_at and not privileged then
    raise exception 'A group is removed by deleting it, not by marking it.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists church_groups_guard on public.church_groups;
create trigger church_groups_guard
  before insert or update on public.church_groups
  for each row execute function public.pw_guard_church_group();

-- The founder becomes the group's first admin, and the group gets its invite
-- code, in the same transaction as the group itself. A trigger rather than a
-- step in the app so the two cannot come apart: there is no way to create a
-- group, by any path, that ends up with nobody looking after it.
--
-- Definer because the membership it writes is an admin row, which no member
-- may insert for themselves. It writes exactly one, keyed by the caller's own
-- id and the id of the row that fired it.
create or replace function public.pw_church_group_founded()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.church_group_invites (group_id, code)
  values (new.id, public.pw_new_invite_code())
  on conflict (group_id) do nothing;

  if new.created_by is not null then
    insert into public.church_group_members (group_id, user_id, role, status)
    values (new.id, new.created_by, 'admin', 'active')
    on conflict (group_id, user_id) do nothing;
  end if;
  return null;
end;
$$;

drop trigger if exists church_groups_founded on public.church_groups;
create trigger church_groups_founded
  after insert on public.church_groups
  for each row execute function public.pw_church_group_founded();

-- -------------------------------------------- church_group_members guards ---
--
-- The shape of `prevent_self_role_change()` on `profiles`, for the same reason:
-- RLS decides which rows a person may touch, and this decides what they may
-- do to them.
--
--   service_role / postgres     → allowed (tooling, and the definer functions
--                                 in this file)
--   changing your own role      → refused, whoever you are
--   anyone but a group admin
--     changing a role           → refused
--
-- The policies already keep a plain member away from UPDATE entirely. This is
-- the second wall, so self-promotion stays impossible even if a later policy
-- opens a path to it.
create or replace function public.pw_guard_group_membership()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('service_role', 'postgres') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.joined_at := now();
    return new;
  end if;

  if new.group_id is distinct from old.group_id
     or new.user_id is distinct from old.user_id
     or new.joined_at is distinct from old.joined_at
  then
    raise exception 'A membership cannot be moved or backdated.'
      using errcode = '42501';
  end if;

  if new.role is distinct from old.role then
    if auth.uid() = new.user_id then
      raise exception
        'You cannot change your own role in a group. Ask another admin to do it.'
        using errcode = '42501';
    end if;
    if not public.is_group_admin(new.group_id) then
      raise exception 'Only a group admin can change a member''s role.'
        using errcode = '42501';
    end if;
  end if;

  -- Your own standing is somebody else's call too: an admin cannot quietly
  -- set themselves to pending or banned and hand the group to the next in line
  -- without saying so. Leaving is the honest path, and it is a delete.
  if new.status is distinct from old.status and auth.uid() = new.user_id then
    raise exception 'You cannot change your own standing in a group.'
      using errcode = '42501';
  end if;

  -- Tenure starts when somebody is let in, not when they knocked.
  if old.status = 'pending' and new.status = 'active' then
    new.joined_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists church_group_members_guard on public.church_group_members;
create trigger church_group_members_guard
  before insert or update on public.church_group_members
  for each row execute function public.pw_guard_group_membership();

-- ---------------------------------------------------------- succession ---
--
-- A group whose last active admin goes — by leaving, being removed, or
-- deleting their account (which cascades here from `profiles`) — is not left
-- with nobody able to approve a request or answer a report.
--
--   1. If an active admin remains, nothing happens.
--   2. Otherwise the longest-tenured active member is promoted. Tenure is
--      `joined_at`, which the server sets, so it cannot be gamed.
--   3. If there are no active members at all, the group is soft-deleted:
--      hidden from everyone but app admins, its scripture no longer
--      delivered, and its rows kept so a mistaken removal can be undone by
--      hand.
--
-- Definer because the promotion and the soft delete are writes the departing
-- member — or GoTrue, mid-account-deletion — has no policy for. The group row
-- is locked first so two members leaving at once cannot both conclude that
-- the other is still there.
create or replace function public.pw_group_succession()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  gid uuid := old.group_id;
  heir uuid;
begin
  -- Only an active admin ceasing to be one can leave a group headless, and
  -- only a departure can leave it empty.
  if tg_op = 'UPDATE'
     and not (old.role = 'admin' and old.status = 'active'
              and (new.role <> 'admin' or new.status <> 'active'))
  then
    return null;
  end if;

  -- Gone already: this delete is the group itself cascading away, or the
  -- group was soft-deleted before.
  perform 1 from public.church_groups g
   where g.id = gid and g.deleted_at is null
   for update;
  if not found then
    return null;
  end if;

  if exists (
    select 1 from public.church_group_members m
     where m.group_id = gid and m.role = 'admin' and m.status = 'active'
  ) then
    return null;
  end if;

  select m.user_id into heir
    from public.church_group_members m
   where m.group_id = gid and m.status = 'active'
   order by m.joined_at, m.user_id
   limit 1;

  if heir is not null then
    update public.church_group_members
       set role = 'admin'
     where group_id = gid and user_id = heir;
    return null;
  end if;

  update public.church_groups
     set deleted_at = now()
   where id = gid;
  return null;
end;
$$;

drop trigger if exists church_group_members_succession on public.church_group_members;
create trigger church_group_members_succession
  after delete or update of role, status on public.church_group_members
  for each row execute function public.pw_group_succession();

-- -------------------------------------------------- church_groups policies ---

-- Discoverable groups to any signed-in member; hidden ones to the people in
-- them (including someone whose request is waiting, who should be able to see
-- what they asked to join).
drop policy if exists "Groups readable where discoverable or joined" on public.church_groups;
create policy "Groups readable where discoverable or joined"
  on public.church_groups for select to authenticated
  using (
    deleted_at is null
    and (is_discoverable
         or public.pw_my_group_status(id) in ('active', 'pending'))
  );

-- Oversight. Includes soft-deleted groups, so a report about one can still be
-- opened.
drop policy if exists "Admins read all groups" on public.church_groups;
create policy "Admins read all groups"
  on public.church_groups for select to authenticated
  using (public.pw_is_admin());

-- Anyone signed in may start one, as themselves. The founder's admin row is
-- written by `pw_church_group_founded`, not by the client.
drop policy if exists "Members create groups" on public.church_groups;
create policy "Members create groups"
  on public.church_groups for insert to authenticated
  with check (created_by = auth.uid() and deleted_at is null);

-- Suspension, on the same terms as everywhere else.
drop policy if exists "Suspended members do not create groups" on public.church_groups;
create policy "Suspended members do not create groups"
  on public.church_groups as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

drop policy if exists "Group admins edit their group" on public.church_groups;
create policy "Group admins edit their group"
  on public.church_groups for update to authenticated
  using (deleted_at is null and public.is_group_admin(id))
  with check (public.is_group_admin(id));

drop policy if exists "Group admins delete their group" on public.church_groups;
create policy "Group admins delete their group"
  on public.church_groups for delete to authenticated
  using (public.is_group_admin(id));

-- The takedown: what an upheld report about a group ends in.
drop policy if exists "Admins remove groups" on public.church_groups;
create policy "Admins remove groups"
  on public.church_groups for delete to authenticated
  using (public.pw_is_admin());

-- ------------------------------------------- church_group_members policies ---

drop policy if exists "Members read own memberships" on public.church_group_members;
create policy "Members read own memberships"
  on public.church_group_members for select to authenticated
  using (user_id = auth.uid());

-- The roster: active members, to the other active members.
drop policy if exists "Members read their group's roster" on public.church_group_members;
create policy "Members read their group's roster"
  on public.church_group_members for select to authenticated
  using (status = 'active' and public.is_group_member(group_id));

-- Group admins also see who is waiting and who is banned.
drop policy if exists "Group admins read their whole roster" on public.church_group_members;
create policy "Group admins read their whole roster"
  on public.church_group_members for select to authenticated
  using (public.is_group_admin(group_id));

drop policy if exists "Admins read all memberships" on public.church_group_members;
create policy "Admins read all memberships"
  on public.church_group_members for select to authenticated
  using (public.pw_is_admin());

-- Joining: your own row, as a member, with the status the group's policy
-- dictates. A client that sends 'active' for a request-only group, or 'admin'
-- for itself, is refused here.
drop policy if exists "Members join groups" on public.church_group_members;
create policy "Members join groups"
  on public.church_group_members for insert to authenticated
  with check (
    user_id = auth.uid()
    and role = 'member'
    and status = public.pw_group_join_status(group_id)
  );

drop policy if exists "Suspended members do not join groups" on public.church_group_members;
create policy "Suspended members do not join groups"
  on public.church_group_members as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

-- Approving, promoting, demoting, banning: a group's admins, in their group.
-- No path for a member to update their own row at all.
drop policy if exists "Group admins manage memberships" on public.church_group_members;
create policy "Group admins manage memberships"
  on public.church_group_members for update to authenticated
  using (public.is_group_admin(group_id))
  with check (public.is_group_admin(group_id));

-- Leaving is deleting your own row — unless you were banned, in which case
-- leaving and rejoining would be a way round the ban. Admins remove anyone in
-- their group.
drop policy if exists "Members leave, admins remove" on public.church_group_members;
create policy "Members leave, admins remove"
  on public.church_group_members for delete to authenticated
  using (
    (user_id = auth.uid() and status <> 'banned')
    or public.is_group_admin(group_id)
  );

-- ------------------------------------------- church_group_invites policies ---

drop policy if exists "Group admins read their invite code" on public.church_group_invites;
create policy "Group admins read their invite code"
  on public.church_group_invites for select to authenticated
  using (public.is_group_admin(group_id));

-- ----------------------------------------------------------- read shapes ---
--
-- What a group looks like in a list, joined for the viewer. The membership
-- columns ride along so a row can carry its own Join / Leave without a second
-- query — `member_card`'s bargain, for groups.

drop function if exists public.search_church_groups(text, int);
drop function if exists public.my_church_groups();
drop function if exists public.church_group_detail(uuid);
drop function if exists public.church_groups_for_member(uuid);
drop function if exists public.preview_church_group(text);
drop function if exists public.join_church_group_with_code(text);
drop function if exists public.create_church_group(text, text, text, boolean, text);
drop type if exists public.church_group_card cascade;

create type public.church_group_card as (
  id              uuid,
  name            text,
  slug            text,
  description     text,
  avatar_url      text,
  cover_url       text,
  city            text,
  is_discoverable boolean,
  join_policy     text,
  created_at      timestamptz,
  member_count    integer,
  my_role         text,
  my_status       text
);

-- Finding your church. Discoverable groups only — a hidden group you belong to
-- is in "your churches", not in a search a stranger could run. An empty query
-- lists the largest groups first: unlike people, a group that chose to be
-- discoverable has asked to be listed.
create function public.search_church_groups(
  query       text default '',
  limit_count int default 30
)
returns setof public.church_group_card
language sql
stable
as $$
  with q as (select lower(btrim(coalesce(query, ''))) as term)
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    coalesce(public.pw_group_member_count(g.id), 0),
    mine.role,
    mine.status
  from public.church_groups g
  cross join q
  left join public.church_group_members mine
         on mine.group_id = g.id and mine.user_id = auth.uid()
  where g.deleted_at is null
    and g.is_discoverable
    and (
      q.term = ''
      or lower(g.name) like q.term || '%'
      or lower(g.name) like '% ' || q.term || '%'
      or lower(g.name) like '%' || q.term || '%'
      or lower(g.city) like '%' || q.term || '%'
    )
  order by
    case
      when q.term = '' then 0
      when lower(g.name) like q.term || '%' then 0
      when lower(g.name) like '% ' || q.term || '%' then 1
      else 2
    end,
    coalesce(public.pw_group_member_count(g.id), 0) desc,
    g.name,
    g.id
  limit greatest(1, least(coalesce(limit_count, 30), 50));
$$;

-- The groups the caller is in, or has asked to join. Banned rows are left out:
-- a group that banned you is not one of "your churches".
create function public.my_church_groups()
returns setof public.church_group_card
language sql
stable
as $$
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    coalesce(public.pw_group_member_count(g.id), 0),
    mine.role,
    mine.status
  from public.church_group_members mine
  join public.church_groups g on g.id = mine.group_id
  where mine.user_id = auth.uid()
    and mine.status in ('active', 'pending')
    and g.deleted_at is null
  order by (mine.status = 'active') desc, g.name, g.id;
$$;

-- One group, or no rows if the caller may not see it.
create function public.church_group_detail(group_id uuid)
returns setof public.church_group_card
language sql
stable
as $$
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    coalesce(public.pw_group_member_count(g.id), 0),
    mine.role,
    mine.status
  from public.church_groups g
  left join public.church_group_members mine
         on mine.group_id = g.id and mine.user_id = auth.uid()
  where g.id = church_group_detail.group_id;
$$;

-- The churches another member belongs to, as far as the viewer is entitled to
-- know: their active memberships in discoverable groups, plus any hidden group
-- the viewer is in too. Nothing for a member the viewer has blocked or been
-- blocked by, and nothing for a suspended one.
--
-- Definer because the target's membership rows are not readable to a
-- non-member under the roster policy — and that is the policy working: this
-- function is the narrow, deliberate exception for discoverable groups, whose
-- members are listed on their profile the way a church is listed on it.
create function public.church_groups_for_member(target uuid)
returns setof public.church_group_card
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    (select count(*)::int from public.church_group_members c
      where c.group_id = g.id and c.status = 'active'),
    viewer.role,
    viewer.status
  from public.church_group_members theirs
  join public.church_groups g on g.id = theirs.group_id
  join public.profiles p on p.id = theirs.user_id
  left join public.church_group_members viewer
         on viewer.group_id = g.id and viewer.user_id = auth.uid()
  where auth.uid() is not null
    and theirs.user_id = target
    and theirs.status = 'active'
    and g.deleted_at is null
    and (g.is_discoverable or viewer.status = 'active')
    and (p.status = 'active' or target = auth.uid())
    and not public.pw_is_blocked(target)
  order by g.name, g.id;
$$;

-- What an invite code opens, shown before anyone commits to joining.
create function public.preview_church_group(invite_code text)
returns setof public.church_group_card
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    (select count(*)::int from public.church_group_members c
      where c.group_id = g.id and c.status = 'active'),
    mine.role,
    mine.status
  from public.church_group_invites i
  join public.church_groups g on g.id = i.group_id
  left join public.church_group_members mine
         on mine.group_id = g.id and mine.user_id = auth.uid()
  where auth.uid() is not null
    and i.code = upper(btrim(replace(coalesce(invite_code, ''), '-', '')))
    and g.deleted_at is null;
$$;

-- Joining by invite code: the only way into a hidden group. The code admits
-- the caller to the group; the group's own join policy still decides whether
-- they are in or waiting.
create function public.join_church_group_with_code(invite_code text)
returns setof public.church_group_card
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  gid uuid;
  join_rule text;
  existing text;
begin
  if auth.uid() is null or not public.is_active(auth.uid()) then
    raise exception 'Sign in with an active account to join a group.'
      using errcode = '42501';
  end if;

  select g.id, g.join_policy into gid, join_rule
    from public.church_group_invites i
    join public.church_groups g on g.id = i.group_id
   where i.code = upper(btrim(replace(coalesce(invite_code, ''), '-', '')))
     and g.deleted_at is null;

  if gid is null then
    raise exception 'That invite code doesn''t match a group.'
      using errcode = 'P0002';
  end if;

  select m.status into existing
    from public.church_group_members m
   where m.group_id = gid and m.user_id = auth.uid();

  if existing = 'banned' then
    raise exception 'You can''t rejoin this group.' using errcode = '42501';
  end if;

  if existing is null then
    insert into public.church_group_members (group_id, user_id, role, status)
    values (gid, auth.uid(), 'member',
            case join_rule when 'open' then 'active' else 'pending' end);
  end if;

  return query select * from public.preview_church_group(invite_code);
end;
$$;

-- Starting a group, returning it. The insert itself goes through the same
-- guard and founding trigger as a direct one; this exists because a hidden
-- group is not yet readable to its founder at the instant PostgREST checks
-- the RETURNING row — the founder's membership is written by an AFTER trigger
-- — so `insert … select` from the client would fail on its own read policy.
create function public.create_church_group(
  group_name         text,
  group_city         text default '',
  group_about        text default '',
  group_discoverable boolean default true,
  group_join_policy  text default 'open'
)
returns setof public.church_group_card
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  gid uuid;
begin
  if auth.uid() is null or not public.is_active(auth.uid()) then
    raise exception 'Sign in with an active account to start a group.'
      using errcode = '42501';
  end if;

  insert into public.church_groups
    (name, city, description, is_discoverable, join_policy, created_by)
  values
    (btrim(group_name), btrim(coalesce(group_city, '')),
     btrim(coalesce(group_about, '')), coalesce(group_discoverable, true),
     coalesce(group_join_policy, 'open'), auth.uid())
  returning id into gid;

  return query
  select
    g.id, g.name, g.slug, g.description, g.avatar_url, g.cover_url, g.city,
    g.is_discoverable, g.join_policy, g.created_at,
    1, 'admin'::text, 'active'::text
  from public.church_groups g
  where g.id = gid;
end;
$$;

-- A fresh invite code, for when the old one has gone further than intended.
-- Invoker: the update policy below is what limits it to the group's admins.
drop policy if exists "Group admins rotate their invite code" on public.church_group_invites;
create policy "Group admins rotate their invite code"
  on public.church_group_invites for update to authenticated
  using (public.is_group_admin(group_id))
  with check (public.is_group_admin(group_id));

create or replace function public.rotate_church_group_invite(group_id uuid)
returns text
language sql
volatile
as $$
  update public.church_group_invites i
     set code = public.pw_new_invite_code(), rotated_at = now()
   where i.group_id = rotate_church_group_invite.group_id
  returning i.code;
$$;

-- The roster, with each person's byline. Invoker: which rows come back is the
-- roster policy's decision — active members to fellow members, everything to
-- the group's admins — and blocked members drop out through the profiles
-- policy, exactly as they do everywhere else.
create or replace function public.church_group_roster(group_id uuid)
returns table (
  profile   jsonb,
  role      text,
  status    text,
  joined_at timestamptz
)
language sql
stable
as $$
  select
    jsonb_build_object(
      'id', p.id,
      'full_name', p.full_name,
      'avatar_url', p.avatar_url,
      'handle', p.handle,
      'bio', p.bio,
      'church', p.church,
      'role', p.role,
      'status', p.status,
      'created_at', p.created_at
    ),
    m.role,
    m.status,
    m.joined_at
  from public.church_group_members m
  join public.profiles p on p.id = m.user_id
  where m.group_id = church_group_roster.group_id
  order by
    (m.status = 'pending') desc,
    (m.role = 'admin') desc,
    m.joined_at,
    p.id;
$$;

grant execute on function public.search_church_groups(text, int) to authenticated;
grant execute on function public.my_church_groups() to authenticated;
grant execute on function public.church_group_detail(uuid) to authenticated;
grant execute on function public.church_groups_for_member(uuid) to authenticated;
grant execute on function public.preview_church_group(text) to authenticated;
grant execute on function public.join_church_group_with_code(text) to authenticated;
grant execute on function public.create_church_group(text, text, text, boolean, text) to authenticated;
grant execute on function public.rotate_church_group_invite(uuid) to authenticated;
grant execute on function public.church_group_roster(uuid) to authenticated;

-- ---------------------------------------------------------------- images ---
--
-- The avatar and cover, in a bucket of their own keyed by group id — the
-- `avatars` arrangement with the group in place of the member. Public for the
-- same reasons that bucket gives; uuid object names make URLs unguessable.
-- Same privileges note too: run as `postgres`.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('church-groups', 'church-groups', true, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The folder name, as a group the caller administers. A malformed folder is
-- simply "no", rather than a cast error inside a policy.
create or replace function public.pw_is_group_admin_folder(folder text)
returns boolean
language plpgsql
stable
as $$
begin
  if folder is null
     or folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    return false;
  end if;
  return public.is_group_admin(folder::uuid);
end;
$$;

grant execute on function public.pw_is_group_admin_folder(text) to authenticated;

drop policy if exists "Group images readable by authenticated" on storage.objects;
create policy "Group images readable by authenticated"
  on storage.objects for select to authenticated
  using (bucket_id = 'church-groups');

drop policy if exists "Group admins upload group images" on storage.objects;
create policy "Group admins upload group images"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'church-groups'
    and public.pw_is_group_admin_folder((storage.foldername(name))[1])
  );

drop policy if exists "Group admins replace group images" on storage.objects;
create policy "Group admins replace group images"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'church-groups'
    and public.pw_is_group_admin_folder((storage.foldername(name))[1])
  )
  with check (
    bucket_id = 'church-groups'
    and public.pw_is_group_admin_folder((storage.foldername(name))[1])
  );

drop policy if exists "Group admins delete group images" on storage.objects;
create policy "Group admins delete group images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'church-groups'
    and public.pw_is_group_admin_folder((storage.foldername(name))[1])
  );

-- ------------------------------------------------------------ moderation ---
--
-- A group can be reported like a walk or a comment. The excerpt is its name
-- and the "author" its founder, so the console's card reads the same way for
-- all three.

alter table public.moderation_reports
  drop constraint if exists moderation_reports_target_type_check;
alter table public.moderation_reports
  add constraint moderation_reports_target_type_check
  check (target_type in ('activity', 'comment', 'group'));

-- From 20260728050000_admin_functions.sql, with the group branch added. Same
-- return shape, so `create or replace` keeps its grant, and
-- `admin_resolve_report` — which returns `admin_reports(null)` filtered to one
-- row — picks the change up without being touched.
create or replace function public.admin_reports(status_filter text default null)
returns table (
  id                 uuid,
  target_type        text,
  target_id          uuid,
  reason             text,
  status             text,
  created_at         timestamptz,
  resolved_at        timestamptz,
  target_excerpt     text,
  target_author_name text,
  reported_by_name   text
)
language plpgsql
stable
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'The admin console is for admins.' using errcode = '42501';
  end if;

  return query
  select
    r.id,
    r.target_type,
    r.target_id,
    r.reason,
    r.status,
    r.created_at,
    r.resolved_at,
    coalesce(act.excerpt, cmt.excerpt, grp.excerpt),
    coalesce(act.author_name, cmt.author_name, grp.author_name),
    coalesce(nullif(btrim(reporter.full_name), ''), 'A member')
  from public.moderation_reports r
  left join public.profiles reporter on reporter.id = r.reported_by
  left join lateral (
    select
      coalesce(
        nullif(btrim(a.title), ''),
        nullif(btrim(a.note), ''),
        'Untitled walk'
      ) as excerpt,
      coalesce(nullif(btrim(ap.full_name), ''), 'Walker') as author_name
    from public.activities a
    join public.profiles ap on ap.id = a.user_id
    where r.target_type = 'activity' and a.id = r.target_id
  ) act on true
  left join lateral (
    select
      c.body as excerpt,
      coalesce(nullif(btrim(cp.full_name), ''), 'Walker') as author_name
    from public.comments c
    join public.profiles cp on cp.id = c.author_id
    where r.target_type = 'comment' and c.id = r.target_id
  ) cmt on true
  left join lateral (
    select
      g.name || case when g.city <> '' then ', ' || g.city else '' end
        as excerpt,
      coalesce(nullif(btrim(gp.full_name), ''), 'A church group') as author_name
    from public.church_groups g
    left join public.profiles gp on gp.id = g.created_by
    where r.target_type = 'group' and g.id = r.target_id
  ) grp on true
  where status_filter is null or r.status = status_filter
  order by r.created_at desc;
end;
$$;

comment on table public.church_groups is
  'A church''s group. Discoverable groups are listed to every member; hidden '
  'ones are reachable by invite code only (church_group_invites).';
comment on table public.church_group_members is
  'Who is in which group, as what. Admins here administer one group and '
  'nothing else — unrelated to profiles.role.';
comment on table public.church_group_invites is
  'One invite code per group, readable by that group''s admins only.';
