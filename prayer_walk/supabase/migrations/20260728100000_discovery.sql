-- Discovery: how a member finds another member.
--
-- Everything social in this app has been unreachable. `feed_for` returns your
-- own walks plus the walks of people you follow, and there has been no way, in
-- the member app, to find a single person to follow. A new account signed up,
-- followed nobody, and saw an empty feed with no route out of it. Follows,
-- encouragements, comments and the whole moderation apparatus were built for a
-- community that had no door.
--
-- Three reads open it: a search, a strip of suggestions, and — in
-- `20260728090000_visibility_rls_and_reads.sql`, because it had to be written
-- after the visibility rules rather than before them — an explore feed.
--
-- All security invoker, like every other member-facing read here. Which member
-- rows come back is still decided by the policies on `profiles`, and which
-- walks are countable inside them is still decided by the policy on
-- `activities`. These functions add intent, not privilege.

-- ---------------------------------------------------------- prefix indexes ---
--
-- `text_pattern_ops` on `lower(...)` is what makes `lower(col) like 'ana%'` an
-- index scan rather than a walk of the whole membership. It is specifically a
-- *prefix* index and does nothing for the infix fallback below, which is the
-- correct trade: a directory search is overwhelmingly "the first few letters of
-- a name I already know".
create index if not exists profiles_full_name_prefix_idx
  on public.profiles (lower(full_name) text_pattern_ops);

create index if not exists profiles_handle_prefix_idx
  on public.profiles (lower(handle) text_pattern_ops);

-- ------------------------------------------------------------- member_card ---
--
-- What a person looks like in a list of people, the way `activity_card` is what
-- a walk looks like in a list of walks. One shape for search results and for
-- suggestions, so the tile that renders them is written once.
--
-- `is_following` rides along so the row can carry its own Follow button without
-- a second query per result — the N+1 that `activity_card` was built to avoid,
-- in its other form.
--
-- `last_walked_at` is the newest walk *this viewer may see*, which falls out of
-- RLS rather than being arranged: it is null for someone whose walks are all
-- private or followers-only, and that is the honest answer to "has this person
-- been out lately" from where the viewer is standing.
drop function if exists public.search_members(text, uuid, int);
drop function if exists public.suggested_members(uuid, int);
drop type if exists public.member_card cascade;

create type public.member_card as (
  profile        jsonb,
  is_following   boolean,
  follower_count integer,
  last_walked_at timestamptz
);

-- A1 · Find someone by name or handle.
--
-- Case-insensitive, matched three ways and ranked in that order:
--
--   1. the name or handle starts with what was typed — "ana" finds Ana;
--   2. a later word of the name starts with it — "vill" finds Ana Villanueva,
--      because people search by surname and a surname is not a prefix;
--   3. it appears anywhere at all, as the last resort.
--
-- An empty query returns nothing rather than the whole membership. A directory
-- that lists everybody the moment the field is focused is a directory that has
-- published a membership roll, and this app has no such feature by intent.
--
-- Excluded: the viewer themselves (following yourself is not a thing the
-- constraint permits, and offering it is noise), suspended members, and anyone
-- either party has blocked. The block test is belt and braces — the restrictive
-- policy on `profiles` has already removed those rows — but this is a search
-- that reaches strangers, and the two places it could go wrong should both be
-- right.
create function public.search_members(
  query       text,
  viewer      uuid,
  limit_count int default 20
)
returns setof public.member_card
language sql
stable
as $$
  with q as (
    select
      lower(btrim(coalesce(query, ''))) as raw,
      lower(btrim(ltrim(coalesce(query, ''), '@'))) as term
  )
  select
    jsonb_build_object(
      'id', p.id,
      'full_name', p.full_name,
      'avatar_url', p.avatar_url,
      'handle', p.handle,
      'bio', p.bio,
      'parish', p.parish,
      'role', p.role,
      'status', p.status,
      'created_at', p.created_at
    ),
    exists (
      select 1 from public.follows f
      where f.follower_id = viewer and f.followee_id = p.id
    ),
    (select count(*)::int from public.follows f2 where f2.followee_id = p.id),
    (select max(a.started_at) from public.activities a where a.user_id = p.id)
  from public.profiles p, q
  where q.term <> ''
    and p.id <> viewer
    and p.status = 'active'
    and not public.pw_is_blocked(p.id)
    and (
      lower(p.full_name) like q.term || '%'
      or lower(p.handle) like '@' || q.term || '%'
      or lower(p.full_name) like '% ' || q.term || '%'
      or lower(p.full_name) like '%' || q.term || '%'
      or lower(p.handle) like '%' || q.term || '%'
      or lower(p.parish) like '%' || q.term || '%'
    )
  order by
    case
      when lower(p.full_name) like q.term || '%'         then 0
      when lower(p.handle) like '@' || q.term || '%'     then 0
      when lower(p.full_name) like '% ' || q.term || '%' then 1
      else 2
    end,
    p.full_name,
    p.id
  limit greatest(1, least(coalesce(limit_count, 20), 50));
$$;

-- A3 · People to follow.
--
-- The ranking is one rule: whoever most recently posted a walk they chose to
-- make public, that this viewer is not already following. No engagement score,
-- no affinity, nothing a member could not work out from the tile in front of
-- them — a suggestion in a prayer app should be explainable in a sentence, and
-- "they walked publicly on Tuesday" is that sentence.
--
-- Members with nothing public do not appear. Someone who keeps their walks to
-- their followers has not asked to be recommended to strangers, and putting
-- them in a discovery strip on the strength of walks nobody outside can see
-- would be the app volunteering them.
create function public.suggested_members(
  viewer      uuid,
  limit_count int default 8
)
returns setof public.member_card
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
      'parish', p.parish,
      'role', p.role,
      'status', p.status,
      'created_at', p.created_at
    ),
    false,
    (select count(*)::int from public.follows f2 where f2.followee_id = p.id),
    recent.last_public
  from public.profiles p
  join lateral (
    select max(a.started_at) as last_public
    from public.activities a
    where a.user_id = p.id and a.visibility = 'public'
  ) recent on true
  where p.id <> viewer
    and p.status = 'active'
    and recent.last_public is not null
    and not public.pw_is_blocked(p.id)
    and not exists (
      select 1 from public.follows f
      where f.follower_id = viewer and f.followee_id = p.id
    )
  order by recent.last_public desc, p.id
  limit greatest(1, least(coalesce(limit_count, 8), 24));
$$;

grant execute on function public.search_members(text, uuid, int) to authenticated;
grant execute on function public.suggested_members(uuid, int) to authenticated;
