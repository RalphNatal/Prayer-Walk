-- ⛔ DEFERRED — NOT A MIGRATION YET. Do not move into `migrations/` until 1.0.x
-- is no longer in use (1.2.0 at the earliest).
--
-- The contract half of the parish → church rename. The expand half is
-- `migrations/20261016000000_parish_to_church.sql`, which added `church`, kept
-- the old column equal to it with a trigger, and had every profile-shaped read
-- emit both JSON keys so 1.0 and 1.1 could run against one database.
--
-- Applying this removes the old column and the old key. Any 1.0 install still
-- running afterwards fails its profile reads outright (its column list names
-- the dropped column), so check before moving it:
--
--   * the store dashboards show 1.0.x sessions at, or near, zero; or
--   * a minimum-version gate has shipped and is enforcing ≥ 1.1.
--
-- Then rename it with a fresh timestamp, e.g.
-- `migrations/2027MMDDhhmmss_drop_parish.sql`, so it sorts after everything
-- already applied, and `npx supabase db push`.
--
-- What it does, in an order that never leaves a function pointing at a column
-- that is gone: redefine every read without the old key, drop the bridge
-- trigger, redefine the admin edit guard, then drop the column last.

-- -------------------------------------------------------- the read shapes ---
--
-- The four `activity_card` reads from `20260728090000_visibility_rls_and_reads.sql`.
-- Same signature and return type, so `create or replace` keeps their grants.
--
-- The `author` object carries `'church'` only from here on.

-- Walks from everyone `viewer` follows, plus their own, newest first.
--
-- Unchanged in shape from Phase 2. What changed is underneath it: the follow
-- test is still here, but a followed member's `private` walk no longer arrives,
-- because the SELECT policy refuses the row before this query sees it.
create or replace function public.feed_for(
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
      'church', p.church,
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
create or replace function public.explore_feed(
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
      'church', p.church,
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
create or replace function public.activities_for(
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
      'church', p.church,
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
create or replace function public.activity_detail(activity_id uuid, viewer uuid)
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
      'church', p.church,
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

-- ------------------------------------------------------------- discovery ---
--
-- From `20260728100000_discovery.sql`. The search matches the church as well
-- as the name and handle, because "St Joseph" is how most people will look for
-- the people they walk with.

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
create or replace function public.search_members(
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
      'church', p.church,
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
      or lower(p.church) like '%' || q.term || '%'
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
create or replace function public.suggested_members(
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
      'church', p.church,
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

-- --------------------------------------------------------- admin console ---
--
-- From `20260728050000_admin_functions.sql`.

-- The dashboard, whole. The 14-day series is built from `generate_series`
-- left-joined to the counts rather than from the rows alone: a day with no
-- walks has to arrive as a zero, because a chart that silently omits empty days
-- redraws a quiet week as a busy one.
--
-- Days are bucketed in UTC, the same limitation `member_stats` names.
create or replace function public.admin_metrics()
returns table (
  total_members         integer,
  active_this_week      integer,
  activities_logged     integer,
  devotionals_published integer,
  activity_series       jsonb,
  recent_signups        jsonb
)
language plpgsql
stable
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'The admin console is for admins.' using errcode = '42501';
  end if;

  return query
  with bounds as (
    select (now() at time zone 'utc')::date as today
  ),
  days as (
    select generate_series(b.today - 13, b.today, interval '1 day')::date as d
    from bounds b
  ),
  per_day as (
    select (a.started_at at time zone 'utc')::date as d, count(*)::int as n
    from public.activities a, bounds b
    where (a.started_at at time zone 'utc')::date between b.today - 13 and b.today
    group by 1
  ),
  series as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object('date', days.d, 'count', coalesce(per_day.n, 0))
        order by days.d
      ),
      '[]'::jsonb
    ) as js
    from days
    left join per_day on per_day.d = days.d
  ),
  newest as (
    select
      p.created_at,
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
      ) as obj
    from public.profiles p
    order by p.created_at desc
    limit 5
  ),
  signups as (
    select coalesce(jsonb_agg(n.obj order by n.created_at desc), '[]'::jsonb) as js
    from newest n
  )
  select
    (select count(*)::int from public.profiles),
    (select count(distinct a.user_id)::int
       from public.activities a
      where a.started_at >= now() - interval '7 days'),
    (select count(*)::int from public.activities),
    (select count(*)::int from public.devotionals d where d.is_published),
    series.js,
    signups.js
  from series, signups;
end;
$$;

-- The members table with its activity counts already attached. The column names
-- match `profileColumns` so the app's one row→UserProfile mapper reads these
-- rows like any other.
--
-- Nulls mean "no filter". An empty search string means the same, so the screen
-- can send its controller state through unmodified.
drop function if exists public.admin_members(text, text, text, int);
create function public.admin_members(
  search        text default null,
  role_filter   text default null,
  status_filter text default null,
  limit_count   int  default 200
)
returns table (
  id             uuid,
  full_name      text,
  avatar_url     text,
  role           text,
  status         text,
  created_at     timestamptz,
  handle         text,
  bio            text,
  church         text,
  activity_count integer
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
    p.id,
    p.full_name,
    p.avatar_url,
    p.role,
    p.status,
    p.created_at,
    p.handle,
    p.bio,
    p.church,
    counted.n
  from public.profiles p
  left join lateral (
    select count(*)::int as n
    from public.activities a
    where a.user_id = p.id
  ) counted on true
  where (
      search is null or btrim(search) = ''
      or coalesce(p.full_name, '') ilike '%' || btrim(search) || '%'
      or coalesce(p.handle, '')    ilike '%' || btrim(search) || '%'
      or coalesce(p.church, '')    ilike '%' || btrim(search) || '%'
    )
    and (role_filter is null or p.role = role_filter)
    and (status_filter is null or p.status = status_filter)
  order by coalesce(nullif(btrim(p.full_name), ''), 'Walker'), p.created_at
  limit greatest(1, least(coalesce(limit_count, 200), 500));
end;
$$;

grant execute on function public.admin_metrics() to authenticated;
grant execute on function public.admin_members(text, text, text, int) to authenticated;

-- --------------------------------------------------- the bridge comes down ---

drop trigger if exists profiles_sync_church on public.profiles;
drop function if exists public.pw_sync_church_parish();

-- What an admin may edit on another member's row: `role` and `status`, and
-- nothing else. An admin cannot rewrite someone's name, handle, bio, church,
-- avatar or join date — those are the member's own, and the console has no
-- reason to reach them.
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

  -- Someone else's row. Only an admin gets here at all (see the policy in
  -- 20260728010000_admin_role_rules.sql).
  if new.id         is distinct from old.id
     or new.full_name  is distinct from old.full_name
     or new.avatar_url is distinct from old.avatar_url
     or new.handle     is distinct from old.handle
     or new.bio        is distinct from old.bio
     or new.church     is distinct from old.church
     or new.created_at is distinct from old.created_at
  then
    raise exception
      'An admin may change only role and status on another member''s profile.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- ------------------------------------------------------------ the column ---

alter table public.profiles drop column if exists parish;

comment on column public.profiles.church is
  'The member''s church or community, free text and public.';
