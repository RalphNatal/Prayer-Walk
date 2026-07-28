-- ===========================================================================
-- RETRO-CAPTURED MIGRATION — this describes what is ALREADY in the project.
-- ===========================================================================
--
-- `profiles`, its signup trigger, RLS and the two Phase-2 policies were created
-- by hand in the Supabase dashboard and never written down. Anyone rebuilding
-- from `supabase/migrations/` got a database with no `profiles` table, which
-- means no sign-in: the app reads `profiles.role` before it can choose a shell.
--
-- Everything below is written to be a no-op against the live project —
-- `create table if not exists`, `add column if not exists`, `create or replace`,
-- `drop policy if exists ... create policy`. Applying it changes nothing there.
-- Applying it to an empty project reproduces Phase 2.
--
-- The timestamp is earlier than every other migration on purpose. This is the
-- table they all hang off — `activities`, `follows`, `comments` and the rest all
-- reference `profiles(id)` — so a rebuild in filename order has to create it
-- first, even though it was written last.
--
-- The one thing this file deliberately does NOT capture is the old
-- `prevent_self_role_change()`. It is replaced in 20260728010000, and writing
-- down a rule we are about to correct would only invite someone to re-apply the
-- broken one.

-- --------------------------------------------------------------- profiles ---
--
-- One row per signed-in person, keyed by their `auth.users` id. `on delete
-- cascade` is what makes account deletion sweep the app's side clean, since
-- activities, follows, comments and the rest all cascade from here in turn.

create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  avatar_url text,
  role       text not null default 'member' check (role in ('member','admin')),
  created_at timestamptz not null default now()
);

-- The member-editable fields. Already declared in
-- `20260726000000_profiles_member_fields.sql`; repeated here so this file alone
-- reproduces the table as it stands, and harmless because both are `if not
-- exists`.
alter table public.profiles
  add column if not exists handle text unique,
  add column if not exists bio    text not null default '',
  add column if not exists parish text not null default '',
  add column if not exists status text not null default 'active'
    check (status in ('active','suspended'));

-- ------------------------------------------------------- signup provisioning ---
--
-- A profile row has to exist the moment a session does — the router reads
-- `role` before it renders anything, and a missing row would strand a brand new
-- account on the splash.
--
-- `security definer` here is not a way around RLS: this fires on `auth.users`,
-- inside GoTrue's own transaction, where there is no `auth.uid()` yet to write
-- as. It is the one place in this schema that needs it, and it writes exactly
-- one row keyed by the id GoTrue just created — nothing about it is
-- caller-controlled. `search_path` is pinned so a shadowed `profiles` cannot be
-- substituted for the real one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  -- A retried signup, or a row restored by hand, must not fail the sign-in.
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -------------------------------------------------------------------- RLS ---

alter table public.profiles enable row level security;

-- Members-only app: every signed-in person can see every other member. This is
-- what the feed byline, the follow lists and the member search all read.
drop policy if exists "Profiles readable by authenticated" on public.profiles;
create policy "Profiles readable by authenticated"
  on public.profiles for select to authenticated using (true);

-- Your own row, and only your own. `role` and `status` are columns this policy
-- happens to cover; what stops a member writing them is the role trigger (next
-- migration) and the fact that the app never sends `status` on this path.
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);
