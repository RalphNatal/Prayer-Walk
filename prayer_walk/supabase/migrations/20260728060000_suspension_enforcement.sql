-- Suspension, made to mean something.
--
-- `profiles.status` has existed since Phase 2 and has never been enforced
-- anywhere: a suspended member could comment, encourage, follow and record
-- exactly as before. Suspending was a label, not a consequence.
--
-- These are RESTRICTIVE policies, which is the whole point. Postgres ORs
-- permissive policies together, so a new permissive policy could only ever
-- widen access — there is no way to tighten by adding one. Restrictive policies
-- are ANDed with whatever else is there, so each rule below is layered on top
-- of the existing member policies without editing, weakening or replacing any
-- of them. Remove these six policies and Phase 2's rules are exactly as they
-- were.
--
-- Reading is untouched, deliberately. A suspended member can still open the
-- app, see their own walks and read the feed. What they cannot do is add
-- anything to it.

-- ------------------------------------------------------------ is_active() ---
--
-- Security invoker, like `is_admin()`, and safe for the same reason: the
-- profiles SELECT policy is `using (true)` and does not itself consult
-- profiles.
--
-- A caller with no profile row is not active. That case should not arise — the
-- signup trigger provisions one — but "no row" resolving to "allowed" is not a
-- default worth having in a rule like this.
create or replace function public.is_active(uid uuid default auth.uid())
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.status = 'active'
  );
$$;

grant execute on function public.is_active(uuid) to authenticated;

-- ------------------------------------------------------------- activities ---

drop policy if exists "Suspended members record nothing" on public.activities;
create policy "Suspended members record nothing"
  on public.activities as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

-- --------------------------------------------------------------- comments ---
--
-- Insert and update both: editing an existing comment into something else is
-- the same act by another route.

drop policy if exists "Suspended members do not comment" on public.comments;
create policy "Suspended members do not comment"
  on public.comments as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

drop policy if exists "Suspended members do not edit comments" on public.comments;
create policy "Suspended members do not edit comments"
  on public.comments as restrictive for update to authenticated
  using (public.is_active(auth.uid()))
  with check (public.is_active(auth.uid()));

-- --------------------------------------------------------- encouragements ---

drop policy if exists "Suspended members do not encourage" on public.encouragements;
create policy "Suspended members do not encourage"
  on public.encouragements as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

-- ---------------------------------------------------------------- follows ---

drop policy if exists "Suspended members do not follow" on public.follows;
create policy "Suspended members do not follow"
  on public.follows as restrictive for insert to authenticated
  with check (public.is_active(auth.uid()));

-- ------------------------------------------------------ moderation reports ---
--
-- Filing a report is the one write a suspended member keeps. Someone under
-- suspension can still be the person who noticed something, and taking that
-- away punishes the queue rather than them.
