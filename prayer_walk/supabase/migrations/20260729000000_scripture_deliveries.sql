-- What scripture a member has already been given, so a walk can stop repeating.
--
-- Delivery on a walk used to leave no trace beyond the waypoint written onto
-- the activity. The recorder reshuffled the whole library at the start of every
-- walk, which guaranteed no repeat *within* a walk and guaranteed one almost
-- immediately *across* walks: two independent draws of twelve prompts from a
-- pool of forty-seven collide 98% of the time. This table is the memory that
-- makes "unseen first, then least recently seen" possible.
--
-- PRIVACY
-- -------
-- Owner-only, both directions. What scripture somebody received — and when, and
-- how often they walked — is devotional practice, not activity data. It is not
-- readable by followers, not surfaced in a feed or on a profile, and not
-- readable by admins: the admin scripture screen curates the library, and never
-- needs to know who received what. There is deliberately no policy granting a
-- role any wider read, and nothing in the app joins this table to a public one.
--
-- OFFLINE
-- -------
-- This table is a *mirror*, never the source of truth during a walk. The device
-- keeps its own record in `shared_preferences` and consults that; rows arrive
-- here opportunistically afterwards. A walk on a phone with no signal selects
-- from local history and syncs later, and a failed sync costs nothing but
-- eventual cross-device continuity. Nothing on a trail waits on this table.

create table if not exists public.scripture_deliveries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,

  -- Not a foreign key to `scripture_prompts` on purpose. A prompt an admin
  -- later unpublishes or deletes is still a prompt this member has read, and
  -- losing that would make a deleted verse look unseen and bring it back to the
  -- top of the queue. History outlives the library it refers to.
  prompt_id    text not null,

  -- Which walk it arrived on. Nullable because a delivery can be synced after
  -- the activity it belonged to failed to save, and because history is worth
  -- keeping even when the walk it came from is not.
  activity_id  uuid references public.activities(id) on delete set null,

  delivered_at timestamptz not null default now()
);

alter table public.scripture_deliveries enable row level security;

-- The selection query: "everything this member has seen, newest first, per
-- prompt". Ordering `delivered_at` descending in the index itself is what makes
-- the least-recently-seen ranking cheap.
create index if not exists scripture_deliveries_user_prompt_idx
  on public.scripture_deliveries (user_id, prompt_id, delivered_at desc);

-- Owner-only. Four narrow policies rather than one `for all`, so a widening
-- later has to be written deliberately rather than inherited.
create policy "Members read own scripture deliveries"
  on public.scripture_deliveries for select to authenticated
  using (auth.uid() = user_id);

create policy "Members insert own scripture deliveries"
  on public.scripture_deliveries for insert to authenticated
  with check (auth.uid() = user_id);

create policy "Members update own scripture deliveries"
  on public.scripture_deliveries for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Delete is the "start the library fresh" control in scripture settings. A
-- member may deliberately want to walk the same passages again.
create policy "Members delete own scripture deliveries"
  on public.scripture_deliveries for delete to authenticated
  using (auth.uid() = user_id);

comment on table public.scripture_deliveries is
  'Owner-only record of which scripture prompts a member has received, so '
  'selection can prefer unseen and least-recently-seen passages across walks. '
  'A mirror of on-device history, never read on the critical path of a walk. '
  'Never expose through a feed, profile, admin screen or join.';

comment on column public.scripture_deliveries.prompt_id is
  'Deliberately not a foreign key: history must outlive a prompt an admin '
  'unpublishes or deletes, or a removed verse would look unseen and return.';
