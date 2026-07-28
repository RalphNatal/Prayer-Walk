-- Who may administer whom.
--
-- ⚠️ This migration CHANGES TWO EXISTING SECURITY RULES. Read before applying.
--
-- Phase 2 shipped a `profiles` table that was correct for a members-only app
-- and wrong for an admin console:
--
--   1. `prevent_self_role_change()` refused every role change unless the caller
--      was `service_role` or `postgres`. An admin acting through the app is
--      `authenticated`, so no role change could ever be made from the console.
--      The intent was to stop self-promotion, not to stop administering.
--
--   2. `profiles` had exactly one update policy — `auth.uid() = id`. Suspending
--      a member matched zero rows and reported success, which is the worst
--      shape a security failure can take.
--
-- Both are fixed here. The rule that mattered is kept intact and, if anything,
-- tightened: after this migration nobody — member or admin — can change their
-- own role by any path the app can reach.

-- ------------------------------------------------------------- is_admin() ---
--
-- The one definition of "is an admin", so a policy, a trigger and an RPC guard
-- cannot drift into three different answers.
--
-- Security INVOKER on purpose. It is used inside policies on `profiles`, which
-- reads `profiles` — safe only because the SELECT policy on that table is
-- `using (true)` and so does not itself consult `profiles`. The chain
-- terminates in one step; there is no policy recursion here. If a future
-- migration ever narrows the profiles SELECT policy, this function has to be
-- revisited at the same time.
create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.role = 'admin'
  );
$$;

grant execute on function public.is_admin(uuid) to authenticated;

-- ------------------------------------------------------------ B2 · the role rule ---
--
-- Three answers, in order:
--   service_role / postgres  → allowed (dashboard, CLI, out-of-band tooling)
--   changing your own role   → refused, whoever you are
--   an admin, another's row  → allowed
--   anyone else              → refused
--
-- Refusing an admin their own row is not an oversight. It closes self-promotion
-- for good (a member who somehow reached this path still cannot lift
-- themselves), and it means the last admin cannot demote themselves and lock
-- the console — there is always at least one admin left.
--
-- Deliberately NOT `security definer`: `current_user` has to keep reporting the
-- caller, which is the whole basis of the first branch.
create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
as $$
begin
  -- Most updates are not role changes at all — an edited bio, a suspension.
  if new.role is not distinct from old.role then
    return new;
  end if;

  if current_user in ('service_role', 'postgres') then
    return new;
  end if;

  if auth.uid() = new.id then
    raise exception
      'You cannot change your own role. Ask another admin to do it.'
      using errcode = '42501';
  end if;

  if public.is_admin(auth.uid()) then
    return new;
  end if;

  raise exception 'Only an admin can change a member''s role.'
    using errcode = '42501';
end;
$$;

drop trigger if exists prevent_self_role_change on public.profiles;
create trigger prevent_self_role_change
  before update on public.profiles
  for each row execute function public.prevent_self_role_change();

-- --------------------------------------------------- B3 · what an admin may edit ---
--
-- RLS grants or refuses a whole row; it cannot say "these columns only". So the
-- policy opens another member's row to an admin, and this trigger states what
-- the console is actually allowed to touch there: `role` and `status`. Nothing
-- else. An admin cannot rewrite someone's name, handle, bio, parish, avatar or
-- join date — those are the member's own, and the console has no reason to
-- reach them.
create or replace function public.restrict_admin_profile_edits()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('service_role', 'postgres') then
    return new;
  end if;

  -- Your own row: the ordinary Edit profile path, unchanged.
  if auth.uid() = new.id then
    return new;
  end if;

  -- Someone else's row. Only an admin gets here at all (see the policy below).
  if new.id         is distinct from old.id
     or new.full_name  is distinct from old.full_name
     or new.avatar_url is distinct from old.avatar_url
     or new.handle     is distinct from old.handle
     or new.bio        is distinct from old.bio
     or new.parish     is distinct from old.parish
     or new.created_at is distinct from old.created_at
  then
    raise exception
      'An admin may change only role and status on another member''s profile.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists restrict_admin_profile_edits on public.profiles;
create trigger restrict_admin_profile_edits
  before update on public.profiles
  for each row execute function public.restrict_admin_profile_edits();

-- The admin update policy, added ALONGSIDE "Users can update own profile" —
-- which is left exactly as it was. `id <> auth.uid()` keeps the two disjoint:
-- your own row goes through the member policy and the member rules, always.
drop policy if exists "Admins update other members" on public.profiles;
create policy "Admins update other members"
  on public.profiles for update to authenticated
  using (public.is_admin(auth.uid()) and id <> auth.uid())
  with check (public.is_admin(auth.uid()) and id <> auth.uid());
