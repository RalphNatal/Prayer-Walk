-- The visibility rules themselves, and the reads that honour them.
--
-- ⚠️ This migration REPLACES AN EXISTING RLS POLICY. Read before applying.
--
-- `20260726010000_activities.sql` created:
--
--     create policy "Activities readable by authenticated users"
--       on public.activities for select to authenticated using (true);
--
-- That policy is dropped here. Every signed-in account could read every route
-- ever recorded, which is what made a GPS trace beginning at somebody's front
-- door a published home address. Nothing replaced it earlier because there was
-- nothing to replace it with — there was no `visibility` column until
-- `20260728080000_visibility_zones_blocks.sql`, which must already be applied.
--
-- After this migration the app's read surface narrows for everybody, including
-- for rows that were readable a minute ago. That is the point, and it is why
-- the backfill in the previous migration chose `followers` rather than
-- `public`: nobody's exposure widens, and the only thing that changes for an
-- existing member is that strangers stop seeing their history.
--
-- Two things happen here and they are not the same thing:
--
--   * **Visibility** — whether a row is readable at all. Pure RLS, pure
--     security invoker, no exceptions, no service-role path.
--   * **Trimming** — which coordinates of a readable row are handed over. One
--     `security definer` function, argued for where it is written, that can
--     only ever return fewer points than it was given.

-- ------------------------------------------------------ distance, in metres ---
--
-- Haversine. A zone is a circle a few hundred metres across, so the sphere is
-- accurate to well under a metre over that span and PostGIS would be a
-- dependency bought for one comparison.
create or replace function public.pw_meters_between(
  a_lat double precision,
  a_lng double precision,
  b_lat double precision,
  b_lng double precision
)
returns double precision
language sql
immutable
parallel safe
as $$
  select 2 * 6371000 * asin(
    least(1, sqrt(
      power(sin(radians(b_lat - a_lat) / 2), 2)
      + cos(radians(a_lat)) * cos(radians(b_lat))
        * power(sin(radians(b_lng - a_lng) / 2), 2)
    ))
  );
$$;

-- ---------------------------------------------------------- pw_in_any_zone ---
--
-- Whether a point falls inside any of one member's privacy zones.
--
-- **Execute is revoked from `authenticated` and from `public`, deliberately.**
--
-- Granted, this is a home-address oracle: ask it about a grid of candidate
-- points and it draws the circle for you in a few hundred calls. Revoked, it is
-- reachable only from inside `activity_trace_for_viewer` below, which runs as
-- this function's owner and so may call it, and which will only ever test
-- points that are already on a route the caller is allowed to read.
--
-- It is left `security invoker` on purpose. Called directly by a member it sees
-- no zones at all, because `privacy_zones` is owner-only, and answers false to
-- everything. Called from inside the definer function it is running as the
-- owner and sees what it needs to. Both halves fail safe.
create or replace function public.pw_in_any_zone(
  p_owner uuid,
  p_lat   double precision,
  p_lng   double precision
)
returns boolean
language sql
stable
as $$
  select p_lat is not null
     and p_lng is not null
     and exists (
       select 1
         from public.privacy_zones z
        where z.user_id = p_owner
          and public.pw_meters_between(z.lat, z.lng, p_lat, p_lng)
              <= z.radius_meters
     );
$$;

revoke all on function public.pw_in_any_zone(uuid, double precision, double precision)
  from public;
revoke all on function public.pw_in_any_zone(uuid, double precision, double precision)
  from authenticated;

-- ------------------------------------------------ B2 · pw_can_view_activity ---
--
-- The whole visibility rule, in one predicate, so the SELECT policy, the read
-- functions and the trimming function cannot drift into three different
-- answers about the same walk.
--
-- Security invoker, and it takes no viewer parameter: it reads `auth.uid()`
-- directly. A `viewer` argument would be a value the caller supplies, and the
-- one thing a visibility rule must never accept is the caller's own account of
-- who they are. (`feed_for` still takes `viewer`, but only to decide whether to
-- draw the encouragement icon filled in. It cannot widen what comes back.)
--
-- Order matters, and every branch is a decision:
--
--   1. Signed out              → nothing. There is no anonymous read path.
--   2. Your own walk           → always, whatever its visibility, whatever
--                                anyone has done to whom. You cannot be locked
--                                out of your own history.
--   3. An admin                → yes. Moderation has to be able to open the
--                                thing that was reported, and the console's
--                                counts have to count. Note this is read
--                                access to the *row*; the trimming below still
--                                applies to an admin exactly as it does to a
--                                stranger, and `privacy_zones` stays closed to
--                                them, so an admin can no more resolve where a
--                                member lives than anybody else.
--   4. A block, either way     → nothing. Checked before visibility, so a
--                                public walk is still invisible to someone the
--                                walker has blocked.
--   5. A suspended author      → nothing, to anyone but themselves and an
--                                admin. Suspension already stops them adding;
--                                this stops what they added being circulated.
--   6. Then, and only then, the walk's own setting.
create or replace function public.pw_can_view_activity(owner uuid, vis text)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null                     then false
    when auth.uid() = owner                     then true
    when public.pw_is_admin()                   then true
    when public.pw_is_blocked(owner)            then false
    when not exists (
      select 1 from public.profiles p
       where p.id = owner and p.status = 'active'
    )                                           then false
    when vis = 'public'                         then true
    when vis = 'followers'                      then exists (
      select 1 from public.follows f
       where f.follower_id = auth.uid() and f.followee_id = owner
    )
    else false
  end;
$$;

grant execute on function public.pw_can_view_activity(uuid, text) to authenticated;

-- ------------------------------------------------- B2 · the read policy ---

drop policy if exists "Activities readable by authenticated users" on public.activities;
drop policy if exists "Activities readable by their audience" on public.activities;
create policy "Activities readable by their audience"
  on public.activities for select to authenticated
  using (public.pw_can_view_activity(user_id, visibility));

-- A member may not record a walk into a visibility that does not exist, and may
-- not quietly re-point somebody else's. Ownership is already enforced by the
-- Phase 2 policies; the check constraint handles the value. Nothing to add.

-- --------------------------------------- B3 · trimming, on the server side ---
--
-- **The one `security definer` function in the visibility path, and the reason
-- for it.**
--
-- Trimming a route against its owner's zones means reading rows in
-- `privacy_zones` that belong to somebody else. Under RLS the viewer cannot see
-- them — correctly, because those rows say where the owner lives. A
-- security-invoker function would therefore find no zones, trim nothing, and
-- hand the viewer the full trace: the guardrail against a definer function
-- would have produced exactly the leak the feature exists to prevent.
--
-- So this one runs as its owner, and is written so that the extra privilege can
-- only ever *remove* data:
--
--   * it takes an activity id, never a route, so it cannot be fed synthetic
--     points and used as a proximity oracle;
--   * it re-asks `pw_can_view_activity` itself, because RLS is not applying
--     inside it, and returns nothing at all when the answer is no;
--   * it returns coordinates and a boolean. It never returns a zone, a radius,
--     a centre, a count of zones, or anything from which one could be derived —
--     the caller learns that a trace was shortened, not by how much or towards
--     what.
--
-- The trimming itself is from the two ends inward: points are dropped from the
-- start while they fall inside a zone, and from the end while they do, and the
-- middle is kept whole. A walk that passes a zone halfway through keeps those
-- points, and that is the safer of the two options rather than an oversight —
-- cutting a hole in the middle of a trace draws a straight line across the gap
-- whose two ends sit on the circle's edge, which locates the centre far more
-- precisely than the honest curve does.
--
-- Waypoints are different and are filtered wholesale: a waypoint is a point,
-- not a segment, so dropping one leaves no line behind to give it away.
--
-- Distance is not recomputed. The card reports the full recorded walk and says
-- so — see `route_trimmed` on `activity_card`, which the app renders as a line
-- of copy next to the map. The alternative, silently shrinking the number to
-- match the shortened line, would both understate a walk somebody actually did
-- and quietly publish how much was cut, which is a measurement of the zone.
create or replace function public.activity_trace_for_viewer(activity_id uuid)
returns table (route jsonb, waypoints jsonb, route_trimmed boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := auth.uid();
  v_owner uuid;
  v_vis   text;
  v_route jsonb;
  v_wps   jsonb;
  v_kept  jsonb;
  v_wkept jsonb;
  v_n     int;
  v_lo    int;
  v_hi    int;
begin
  select a.user_id,
         a.visibility,
         coalesce(a.route, '[]'::jsonb),
         coalesce(a.waypoints, '[]'::jsonb)
    into v_owner, v_vis, v_route, v_wps
    from public.activities a
   where a.id = activity_trace_for_viewer.activity_id;

  -- No such walk, or none this caller may read. Both return no rows, and the
  -- caller renders the same "not found" either way.
  if not found then
    return;
  end if;
  if not public.pw_can_view_activity(v_owner, v_vis) then
    return;
  end if;

  -- The owner always sees their whole walk. A member who could not see where
  -- their own trace really went would have no way to check that a zone is
  -- covering what they meant it to.
  if v_me = v_owner then
    route := v_route;
    waypoints := v_wps;
    route_trimmed := false;
    return next;
    return;
  end if;

  v_n  := jsonb_array_length(v_route);
  v_lo := 0;
  v_hi := v_n - 1;

  while v_lo <= v_hi and public.pw_in_any_zone(
          v_owner,
          (v_route -> v_lo ->> 0)::double precision,
          (v_route -> v_lo ->> 1)::double precision) loop
    v_lo := v_lo + 1;
  end loop;

  while v_hi >= v_lo and public.pw_in_any_zone(
          v_owner,
          (v_route -> v_hi ->> 0)::double precision,
          (v_route -> v_hi ->> 1)::double precision) loop
    v_hi := v_hi - 1;
  end loop;

  -- A walk that never left the zone leaves the zone with nothing to draw. An
  -- empty route is a state the map already renders — see `Activity.route`.
  if v_lo > v_hi then
    v_kept := '[]'::jsonb;
  else
    v_kept := (
      select coalesce(jsonb_agg(e.value order by e.ord), '[]'::jsonb)
        from jsonb_array_elements(v_route) with ordinality as e(value, ord)
       where e.ord - 1 between v_lo and v_hi
    );
  end if;

  v_wkept := (
    select coalesce(jsonb_agg(w.value order by w.ord), '[]'::jsonb)
      from jsonb_array_elements(v_wps) with ordinality as w(value, ord)
     where not public.pw_in_any_zone(
             v_owner,
             (w.value ->> 'lat')::double precision,
             (w.value ->> 'lng')::double precision)
  );

  route := v_kept;
  waypoints := v_wkept;
  route_trimmed := v_lo > 0
                or v_hi < v_n - 1
                or jsonb_array_length(v_wkept) < jsonb_array_length(v_wps);
  return next;
end;
$$;

grant execute on function public.activity_trace_for_viewer(uuid) to authenticated;

-- ---------------------------------------------------------- the read shapes ---
--
-- Same bargain as `20260727010000_social_graph.sql`: one card shape, one place
-- it is assembled, dropped and recreated together because changing the shape
-- means changing every function that returns it.
--
-- Two columns are new. `visibility` so a walk of your own can carry its own
-- audience without a second query, and `route_trimmed` so the map can say out
-- loud that the line is shorter than the walk was.
--
-- The route and waypoints no longer come off `a` directly. They come from
-- `activity_trace_for_viewer`, which is the only reason any of this is
-- server-side: a client that received the real coordinates and declined to draw
-- them would have already been handed the address.

drop function if exists public.feed_for(uuid, int, timestamptz);
drop function if exists public.activities_for(uuid, uuid, text, int);
drop function if exists public.activity_detail(uuid, uuid);
drop function if exists public.explore_feed(uuid, int, timestamptz);
drop type if exists public.activity_card cascade;

create type public.activity_card as (
  id                    uuid,
  user_id               uuid,
  type                  text,
  title                 text,
  started_at            timestamptz,
  duration_seconds      integer,
  distance_meters       double precision,
  elevation_gain_meters double precision,
  route                 jsonb,
  waypoints             jsonb,
  intentions            jsonb,
  note                  text,
  place_name            text,
  visibility            text,
  route_trimmed         boolean,
  created_at            timestamptz,
  author                jsonb,
  encouragement_count   integer,
  comment_count         integer,
  encouraged_by_viewer  boolean
);

-- Walks from everyone `viewer` follows, plus their own, newest first.
--
-- Unchanged in shape from Phase 2. What changed is underneath it: the follow
-- test is still here, but a followed member's `private` walk no longer arrives,
-- because the SELECT policy refuses the row before this query sees it.
create function public.feed_for(
  viewer uuid,
  limit_count int default 50,
  before timestamptz default null
)
returns setof public.activity_card
language sql
stable
as $$
  select
    a.id,
    a.user_id,
    a.type,
    a.title,
    a.started_at,
    a.duration_seconds,
    a.distance_meters,
    a.elevation_gain_meters,
    coalesce(trace.route, '[]'::jsonb),
    coalesce(trace.waypoints, '[]'::jsonb),
    a.intentions,
    a.note,
    a.place_name,
    a.visibility,
    coalesce(trace.route_trimmed, false),
    a.created_at,
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
    enc.n,
    cmt.n,
    enc.mine
  from public.activities a
  join public.profiles p on p.id = a.user_id
  left join lateral public.activity_trace_for_viewer(a.id) trace on true
  left join lateral (
    select
      count(*)::int as n,
      coalesce(bool_or(e.from_user_id = viewer), false) as mine
    from public.encouragements e
    where e.activity_id = a.id
  ) enc on true
  left join lateral (
    select count(*)::int as n
    from public.comments c
    where c.activity_id = a.id
  ) cmt on true
  where (
      a.user_id = viewer
      or exists (
        select 1
        from public.follows f
        where f.follower_id = viewer and f.followee_id = a.user_id
      )
    )
    and (before is null or a.started_at < before)
  order by a.started_at desc
  limit greatest(1, least(coalesce(limit_count, 50), 200));
$$;

-- A2 · Public walks from members `viewer` does not follow.
--
-- Written after the policy above rather than before it, on purpose: this is the
-- one read in the app that deliberately reaches past the follow graph, so it is
-- the one place a visibility mistake would publish somebody's route to the
-- whole membership. It filters on `visibility = 'public'` explicitly and does
-- not lean on RLS to have done it — RLS is still the boundary, but a query that
-- reaches for strangers' rows should say what it will accept.
--
-- Suspended authors, blocked members and private walks are all already gone by
-- the time this predicate runs. What is added here is: public only, not mine,
-- not anyone I already follow.
create function public.explore_feed(
  viewer uuid,
  limit_count int default 30,
  before timestamptz default null
)
returns setof public.activity_card
language sql
stable
as $$
  select
    a.id,
    a.user_id,
    a.type,
    a.title,
    a.started_at,
    a.duration_seconds,
    a.distance_meters,
    a.elevation_gain_meters,
    coalesce(trace.route, '[]'::jsonb),
    coalesce(trace.waypoints, '[]'::jsonb),
    a.intentions,
    a.note,
    a.place_name,
    a.visibility,
    coalesce(trace.route_trimmed, false),
    a.created_at,
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
    enc.n,
    cmt.n,
    enc.mine
  from public.activities a
  join public.profiles p on p.id = a.user_id
  left join lateral public.activity_trace_for_viewer(a.id) trace on true
  left join lateral (
    select
      count(*)::int as n,
      coalesce(bool_or(e.from_user_id = viewer), false) as mine
    from public.encouragements e
    where e.activity_id = a.id
  ) enc on true
  left join lateral (
    select count(*)::int as n
    from public.comments c
    where c.activity_id = a.id
  ) cmt on true
  where a.visibility = 'public'
    and a.user_id <> viewer
    and p.status = 'active'
    and not exists (
      select 1
      from public.follows f
      where f.follower_id = viewer and f.followee_id = a.user_id
    )
    and (before is null or a.started_at < before)
  order by a.started_at desc
  limit greatest(1, least(coalesce(limit_count, 30), 100));
$$;

-- One member's walks, for History and the profile strip.
--
-- Reading someone else's profile now shows the walks they have shared with you
-- and nothing else — which means a non-follower sees an empty strip where they
-- used to see a history. That is the correction, not a regression.
create function public.activities_for(
  target uuid,
  viewer uuid,
  type_filter text default null,
  limit_count int default 200
)
returns setof public.activity_card
language sql
stable
as $$
  select
    a.id,
    a.user_id,
    a.type,
    a.title,
    a.started_at,
    a.duration_seconds,
    a.distance_meters,
    a.elevation_gain_meters,
    coalesce(trace.route, '[]'::jsonb),
    coalesce(trace.waypoints, '[]'::jsonb),
    a.intentions,
    a.note,
    a.place_name,
    a.visibility,
    coalesce(trace.route_trimmed, false),
    a.created_at,
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
    enc.n,
    cmt.n,
    enc.mine
  from public.activities a
  join public.profiles p on p.id = a.user_id
  left join lateral public.activity_trace_for_viewer(a.id) trace on true
  left join lateral (
    select
      count(*)::int as n,
      coalesce(bool_or(e.from_user_id = viewer), false) as mine
    from public.encouragements e
    where e.activity_id = a.id
  ) enc on true
  left join lateral (
    select count(*)::int as n
    from public.comments c
    where c.activity_id = a.id
  ) cmt on true
  where a.user_id = target
    and (type_filter is null or a.type = type_filter)
  order by a.started_at desc
  limit greatest(1, least(coalesce(limit_count, 200), 500));
$$;

-- A single walk. No rows means it does not exist, or the policy hides it, or
-- one of the two people has blocked the other. The caller turns all of those
-- into the same "not found", which is the only answer that does not confirm
-- something about a walk the reader is not entitled to.
create function public.activity_detail(activity_id uuid, viewer uuid)
returns setof public.activity_card
language sql
stable
as $$
  select
    a.id,
    a.user_id,
    a.type,
    a.title,
    a.started_at,
    a.duration_seconds,
    a.distance_meters,
    a.elevation_gain_meters,
    coalesce(trace.route, '[]'::jsonb),
    coalesce(trace.waypoints, '[]'::jsonb),
    a.intentions,
    a.note,
    a.place_name,
    a.visibility,
    coalesce(trace.route_trimmed, false),
    a.created_at,
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
    enc.n,
    cmt.n,
    enc.mine
  from public.activities a
  join public.profiles p on p.id = a.user_id
  left join lateral public.activity_trace_for_viewer(a.id) trace on true
  left join lateral (
    select
      count(*)::int as n,
      coalesce(bool_or(e.from_user_id = viewer), false) as mine
    from public.encouragements e
    where e.activity_id = a.id
  ) enc on true
  left join lateral (
    select count(*)::int as n
    from public.comments c
    where c.activity_id = a.id
  ) cmt on true
  where a.id = activity_detail.activity_id;
$$;

grant execute on function public.feed_for(uuid, int, timestamptz) to authenticated;
grant execute on function public.explore_feed(uuid, int, timestamptz) to authenticated;
grant execute on function public.activities_for(uuid, uuid, text, int) to authenticated;
grant execute on function public.activity_detail(uuid, uuid) to authenticated;

-- ------------------------------------------------------- a knock-on effect ---
--
-- `member_stats` is unchanged and is now viewer-scoped, because it counts rows
-- in `activities` through the same policy as everything else. Somebody else's
-- profile reports the distance, the streak and the count of the walks *you may
-- see*, not of every walk they have taken.
--
-- Left alone deliberately. Making it `security definer` would restore the old
-- totals, but those totals are derived from private walks and are a channel
-- back out of them: a lifetime distance that moves on a Tuesday says a walk
-- happened on Tuesday. A number that matches the walks on the screen is the
-- honest one, and it is the same rule the rest of this migration follows.
