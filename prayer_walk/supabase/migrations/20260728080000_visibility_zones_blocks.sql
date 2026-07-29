-- Visibility, privacy zones and blocks — the shape of the thing.
--
-- ⚠️ This migration BACKFILLS EXISTING ROWS. Read before applying.
--
-- Until now `activities` had no visibility at all: the SELECT policy was
-- `using (true)`, so every route every member had ever recorded was readable by
-- every signed-in account. A GPS trace that starts and ends at someone's front
-- door is their home address, and the app was publishing it.
--
-- This migration only adds the columns and the tables. It deliberately does not
-- change a single policy on `activities` — that is
-- `20260728090000_visibility_rls_and_reads.sql`, which must be applied
-- immediately after this one. Between the two, the database is exactly as open
-- as it was before; nothing here narrows anything, so applying this half alone
-- cannot break a running app.
--
-- Three things arrive together because they are one idea:
--
--   * `activities.visibility`  — who a walk is for.
--   * `privacy_zones`          — where a walk must not be shown from.
--   * `blocks`                 — who a walk is never for.

-- ------------------------------------------------- B1 · activity visibility ---
--
-- Added nullable, backfilled, then constrained — three statements rather than
-- one `add column ... not null default`. Postgres would have filled the
-- existing rows with the default on its own, but a backfill this consequential
-- should be a line somebody can read and check rather than a side effect of
-- how `alter table` happens to be implemented.
--
-- **Everything existing becomes `followers`, and nothing becomes `public`.**
-- These walks were recorded when the app made no promise either way. Turning
-- that silence into "published to every account on the server" would be this
-- migration deciding, on their behalf, to widen the exposure of people who
-- never asked for it. `followers` is the reading of their intent that cannot
-- hurt anyone: a walk becomes visible to strangers only when its owner says so.

alter table public.activities
  add column if not exists visibility text;

update public.activities
   set visibility = 'followers'
 where visibility is null;

alter table public.activities
  alter column visibility set default 'followers';

alter table public.activities
  alter column visibility set not null;

alter table public.activities
  drop constraint if exists activities_visibility_check;
alter table public.activities
  add constraint activities_visibility_check
  check (visibility in ('private', 'followers', 'public'));

-- Explore reads `visibility = 'public'` ordered by `started_at`; without this
-- it is a sequential scan over every walk on the server to build one page.
create index if not exists activities_visibility_started_idx
  on public.activities (visibility, started_at desc);

-- ------------------------------------------ B1 · the member-level default ---
--
-- What a new walk starts as. Also `followers`: a member opts into a wider
-- audience once, deliberately, rather than discovering afterwards that the
-- setting had been sitting on `public` since they signed up.

alter table public.profiles
  add column if not exists default_activity_visibility text;

update public.profiles
   set default_activity_visibility = 'followers'
 where default_activity_visibility is null;

alter table public.profiles
  alter column default_activity_visibility set default 'followers';

alter table public.profiles
  alter column default_activity_visibility set not null;

alter table public.profiles
  drop constraint if exists profiles_default_visibility_check;
alter table public.profiles
  add constraint profiles_default_visibility_check
  check (default_activity_visibility in ('private', 'followers', 'public'));

-- Whether this member has ever been shown the "a public walk is visible to
-- everyone" explanation. One column rather than a local preference, because the
-- explanation is about a server-side consequence and has to survive a reinstall
-- and a second device. See B4.
alter table public.profiles
  add column if not exists public_walk_notice_seen boolean not null default false;

-- ------------------------------------------------------ B3 · privacy zones ---
--
-- A saved point and a radius. Two of them — home and work — cover the case that
-- matters: a trace whose first and last fixes are the doorway somebody sleeps
-- behind.
--
-- The rows are as sensitive as anything in this database. A zone is not "a
-- place the member finds boring"; it is, by construction, the place they most
-- need a stranger not to have. So the policies below are owner-only for
-- **read** as well as write, with no admin exception. An admin moderating a
-- reported walk needs the walk; they do not need to know where the walker
-- lives, and a console that could show them is a console that leaks the moment
-- an admin account does.
--
-- Note what follows from that: no security-invoker function can trim a route
-- against its owner's zones, because the viewer cannot see those rows. The
-- trimming in the next migration is therefore a narrow `security definer`
-- function that returns *fewer* coordinates and never a zone. That is the one
-- exception, and it is argued for where it is written.

create table if not exists public.privacy_zones (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  label         text not null default 'Home'
                  check (char_length(btrim(label)) between 1 and 60),
  lat           double precision not null check (lat between -90 and 90),
  lng           double precision not null check (lng between -180 and 180),
  -- 200 m is the default the UI offers: large enough to cover a street and its
  -- corner, small enough that a 3 km walk still reads as a walk. The floor
  -- stops a zone so small it hides nothing and reassures anyway; the ceiling
  -- stops one so large it silently deletes whole walks.
  radius_meters integer not null default 200
                  check (radius_meters between 50 and 2000),
  created_at    timestamptz not null default now()
);

create index if not exists privacy_zones_user_idx
  on public.privacy_zones (user_id);

alter table public.privacy_zones enable row level security;

drop policy if exists "Zones readable only by their owner" on public.privacy_zones;
create policy "Zones readable only by their owner"
  on public.privacy_zones for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users create own zones" on public.privacy_zones;
create policy "Users create own zones"
  on public.privacy_zones for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users update own zones" on public.privacy_zones;
create policy "Users update own zones"
  on public.privacy_zones for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users delete own zones" on public.privacy_zones;
create policy "Users delete own zones"
  on public.privacy_zones for delete to authenticated
  using (auth.uid() = user_id);

-- ------------------------------------------------------------ B5 · blocks ---
--
-- Reporting is retrospective: it asks an admin to look at something that has
-- already happened. Blocking is the control a member has *now*, without asking
-- anybody. A community where strangers can reach each other needs both, and the
-- one that has to exist before the strangers arrive is this one.

create table if not exists public.blocks (
  blocker_id uuid not null,
  blocked_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id),
  -- Named rather than inferred, for the reason `follows` names its own: this
  -- table reaches `profiles` twice and PostgREST needs an unambiguous hint to
  -- embed it. The app's select string spells these names out.
  constraint blocks_blocker_id_fkey foreign key (blocker_id)
    references public.profiles(id) on delete cascade,
  constraint blocks_blocked_id_fkey foreign key (blocked_id)
    references public.profiles(id) on delete cascade
);

create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;

-- Only the blocker reads their own list. The blocked party is not handed a
-- queryable roster of who has blocked them — they will infer it from the
-- silence, which is all a block ever promises.
drop policy if exists "Blocks readable by the blocker" on public.blocks;
create policy "Blocks readable by the blocker"
  on public.blocks for select to authenticated
  using (auth.uid() = blocker_id);

drop policy if exists "Users create own blocks" on public.blocks;
create policy "Users create own blocks"
  on public.blocks for insert to authenticated
  with check (auth.uid() = blocker_id);

drop policy if exists "Users delete own blocks" on public.blocks;
create policy "Users delete own blocks"
  on public.blocks for delete to authenticated
  using (auth.uid() = blocker_id);

-- ------------------------------------------------------- pw_is_blocked() ---
--
-- Whether a block exists between the caller and [other], in either direction.
--
-- `security definer` because it has to see rows the caller may not: the point
-- of a block is that it binds the blocked party too, and they cannot read the
-- row that binds them. What it returns is one boolean about a pair the caller
-- is already half of.
--
-- **One parameter, not two.** A two-parameter `pw_is_blocked(a, b)` would let
-- any member enumerate the block graph between strangers. This shape can only
-- answer questions about the caller, which is the only question anything in
-- this database needs to ask.
--
-- ⚠️ The three `security definer` functions in this migration and the next one
-- all depend on being owned by the role that owns the tables they read — the
-- table owner is exempt from RLS, which is what lets them see a row the caller
-- may not. Applying these files as `postgres` in the SQL editor gives that for
-- free. Applying them as some other role would leave the functions running
-- under the caller's own policies, at which point `pw_is_blocked` silently
-- answers false to everything and the block rules stop binding. If these are
-- ever run by a different role, check `\df+` and re-own them.
create or replace function public.pw_is_blocked(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
     and other is not null
     and exists (
       select 1 from public.blocks b
       where (b.blocker_id = auth.uid() and b.blocked_id = other)
          or (b.blocker_id = other       and b.blocked_id = auth.uid())
     );
$$;

grant execute on function public.pw_is_blocked(uuid) to authenticated;

-- --------------------------------------------------------- pw_is_admin() ---
--
-- The same question `is_admin()` answers, asked in a way that is safe to put
-- inside a policy on `profiles`.
--
-- `20260728010000_admin_role_rules.sql` says of `is_admin()`: "safe only
-- because the SELECT policy on that table is `using (true)` ... If a future
-- migration ever narrows the profiles SELECT policy, this function has to be
-- revisited at the same time." This is that migration — the restrictive policy
-- below narrows it — so this is that revisit.
--
-- `security definer` breaks the loop: it reads `profiles` as the function's
-- owner, for whom RLS does not apply, so a policy on `profiles` may call it
-- without the policy being consulted again to answer itself. `is_admin()` is
-- left exactly as it was and stays correct everywhere it is already used; this
-- is the one place that needs the stronger guarantee.
create or replace function public.pw_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

grant execute on function public.pw_is_admin() to authenticated;

-- --------------------------------------------------- pw_activity_owner() ---
--
-- Who recorded a given walk, regardless of whether the caller may read it.
--
-- Needed by the block rules below, and `security definer` for a reason worth
-- stating: a policy that asked `(select user_id from activities where id = ...)`
-- as the caller would be answered by the caller's own read policy. For someone
-- who has been blocked that subquery returns NULL, the block test would compare
-- against nobody, and the rule would pass — the check would be defeated by
-- exactly the situation it exists for.
--
-- What it discloses is one author id for one activity id the caller already
-- holds, which is the id they got from the card they were looking at.
create or replace function public.pw_activity_owner(activity_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select a.user_id
    from public.activities a
   where a.id = pw_activity_owner.activity_id;
$$;

grant execute on function public.pw_activity_owner(uuid) to authenticated;

-- --------------------------------------- B5 · blocking, made to mean something ---
--
-- RESTRICTIVE policies, for the reason the suspension migration gives: Postgres
-- ORs permissive policies together, so nothing added permissively can ever
-- tighten access. Each rule below is ANDed on top of the existing member
-- policies without editing or weakening any of them.

-- A blocked member cannot read the blocker's profile. Their own row and an
-- admin's view are excepted — the first so nobody can lock themselves out of
-- their own account, the second so a block cannot be used to hide from
-- moderation.
drop policy if exists "Blocked members do not read a blocker's profile" on public.profiles;
create policy "Blocked members do not read a blocker's profile"
  on public.profiles as restrictive for select to authenticated
  using (
    id = auth.uid()
    or public.pw_is_admin()
    or not public.pw_is_blocked(id)
  );

-- Neither party may follow the other. Both directions, because a block that
-- only stopped the blocked member would leave the blocker's own follow row
-- sitting in a graph they have said they want out of.
drop policy if exists "Blocked members do not follow" on public.follows;
create policy "Blocked members do not follow"
  on public.follows as restrictive for insert to authenticated
  with check (not public.pw_is_blocked(followee_id));

drop policy if exists "Blocked members do not encourage" on public.encouragements;
create policy "Blocked members do not encourage"
  on public.encouragements as restrictive for insert to authenticated
  with check (not public.pw_is_blocked(public.pw_activity_owner(activity_id)));

drop policy if exists "Blocked members do not comment" on public.comments;
create policy "Blocked members do not comment"
  on public.comments as restrictive for insert to authenticated
  with check (not public.pw_is_blocked(public.pw_activity_owner(activity_id)));

-- Editing an existing comment into something else is the same act by another
-- route — the shape the suspension migration already established.
drop policy if exists "Blocked members do not edit comments" on public.comments;
create policy "Blocked members do not edit comments"
  on public.comments as restrictive for update to authenticated
  using (not public.pw_is_blocked(public.pw_activity_owner(activity_id)))
  with check (not public.pw_is_blocked(public.pw_activity_owner(activity_id)));

-- --------------------------------------------- blocking severs the follow ---
--
-- The policies above stop a *new* follow. This clears the ones already there.
--
-- Without it, a member who blocks someone who was already following them keeps
-- a follower they have said they want gone: the read rules in the next
-- migration would hide the content correctly, but the follower count would
-- still be wrong and the name would still be in the followers list. The block
-- is meant to end the relationship, not to mute one side of it.
-- `security definer`, because the blocker is only allowed to delete their own
-- follow row and this has to remove the other one too.
create or replace function public.pw_block_severs_follow()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.follows f
   where (f.follower_id = new.blocker_id and f.followee_id = new.blocked_id)
      or (f.follower_id = new.blocked_id and f.followee_id = new.blocker_id);
  return null;
end;
$$;

drop trigger if exists blocks_sever_follow on public.blocks;
create trigger blocks_sever_follow
  after insert on public.blocks
  for each row execute function public.pw_block_severs_follow();

-- ---------------------------------------------------- suspension, extended ---
--
-- `20260728060000_suspension_enforcement.sql` stops a suspended member adding
-- to the community. Zones and blocks are the two things they keep: a suspended
-- member still has a home address worth protecting, and still has the right to
-- refuse contact. Neither adds anything to anyone else's feed.
