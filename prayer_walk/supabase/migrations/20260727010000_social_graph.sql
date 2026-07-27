-- Social graph, feed and lifetime stats.
--
-- Three join tables (follows, encouragements, comments) and the server-side
-- reads that keep a feed to one round trip. The counts a card shows live in the
-- join tables, never denormalised onto `activities`: a withdrawn encouragement
-- has to disappear everywhere at once, and a stored counter is one more thing
-- that can be wrong.
--
-- Every function here is `security invoker` (the default) on purpose. These are
-- member-facing reads; RLS is the boundary and must still apply inside them.

-- ------------------------------------------------------------------ follows ---

create table if not exists public.follows (
  follower_id uuid not null,
  followee_id uuid not null,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  constraint no_self_follow check (follower_id <> followee_id),
  -- Named rather than inferred: PostgREST needs an unambiguous hint to embed
  -- `profiles` twice from this table, and the app spells these names out.
  constraint follows_follower_id_fkey foreign key (follower_id)
    references public.profiles(id) on delete cascade,
  constraint follows_followee_id_fkey foreign key (followee_id)
    references public.profiles(id) on delete cascade
);
create index if not exists follows_followee_idx on public.follows (followee_id);

alter table public.follows enable row level security;

drop policy if exists "Follows readable by authenticated" on public.follows;
create policy "Follows readable by authenticated"
  on public.follows for select to authenticated using (true);

drop policy if exists "Users create own follows" on public.follows;
create policy "Users create own follows"
  on public.follows for insert to authenticated with check (auth.uid() = follower_id);

drop policy if exists "Users delete own follows" on public.follows;
create policy "Users delete own follows"
  on public.follows for delete to authenticated using (auth.uid() = follower_id);

-- ----------------------------------------------------------- encouragements ---

create table if not exists public.encouragements (
  id           uuid primary key default gen_random_uuid(),
  activity_id  uuid not null references public.activities(id) on delete cascade,
  from_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  -- One blessing per person per walk. This constraint is what makes the toggle
  -- safe to race: a double tap is a 23505, not a second row.
  unique (activity_id, from_user_id)
);
create index if not exists encouragements_activity_idx
  on public.encouragements (activity_id);

alter table public.encouragements enable row level security;

drop policy if exists "Encouragements readable by authenticated" on public.encouragements;
create policy "Encouragements readable by authenticated"
  on public.encouragements for select to authenticated using (true);

drop policy if exists "Users create own encouragements" on public.encouragements;
create policy "Users create own encouragements"
  on public.encouragements for insert to authenticated with check (auth.uid() = from_user_id);

drop policy if exists "Users delete own encouragements" on public.encouragements;
create policy "Users delete own encouragements"
  on public.encouragements for delete to authenticated using (auth.uid() = from_user_id);

-- ----------------------------------------------------------------- comments ---

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at  timestamptz not null default now()
);
create index if not exists comments_activity_created_idx
  on public.comments (activity_id, created_at);

alter table public.comments enable row level security;

drop policy if exists "Comments readable by authenticated" on public.comments;
create policy "Comments readable by authenticated"
  on public.comments for select to authenticated using (true);

drop policy if exists "Users create own comments" on public.comments;
create policy "Users create own comments"
  on public.comments for insert to authenticated with check (auth.uid() = author_id);

drop policy if exists "Users update own comments" on public.comments;
create policy "Users update own comments"
  on public.comments for update to authenticated
  using (auth.uid() = author_id) with check (auth.uid() = author_id);

-- Comment authors delete their own; activity owners moderate their own walk.
drop policy if exists "Comment author or activity owner deletes" on public.comments;
create policy "Comment author or activity owner deletes"
  on public.comments for delete to authenticated using (
    auth.uid() = author_id
    or auth.uid() = (select a.user_id from public.activities a where a.id = activity_id)
  );

-- ------------------------------------------------------------- read shapes ---
--
-- One card's worth of data. Feed, another member's walks and a single walk all
-- render the same thing, so they all return the same row: the activity, its
-- author, and the two counts plus the viewer's own state.
--
-- Dropped and recreated together — changing the shape means changing all three
-- functions, and `cascade` is what makes this migration re-runnable.

drop function if exists public.feed_for(uuid, int, timestamptz);
drop function if exists public.activities_for(uuid, uuid, text, int);
drop function if exists public.activity_detail(uuid, uuid);
drop function if exists public.member_stats(uuid);
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
  created_at            timestamptz,
  author                jsonb,
  encouragement_count   integer,
  comment_count         integer,
  encouraged_by_viewer  boolean
);

-- Walks from everyone `viewer` follows, plus their own, newest first.
--
-- Keyset pagination on `started_at` via `before` — offsets drift when a walk is
-- recorded mid-scroll. An empty result is ordinary: a new member follows nobody
-- and has walked nowhere.
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
    a.route,
    a.waypoints,
    a.intentions,
    a.note,
    a.place_name,
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

-- One member's walks, for History and the profile strip. Same shape as the
-- feed so a card never has to be assembled twice.
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
    a.route,
    a.waypoints,
    a.intentions,
    a.note,
    a.place_name,
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

-- A single walk. Returns no rows when the id does not exist or RLS hides it —
-- the caller turns that into "not found" rather than a crash.
--
-- The parameter is qualified as `activity_detail.activity_id` wherever it is
-- read: bare `activity_id` would resolve to the column of whichever table is in
-- scope, which is exactly the kind of silent wrong answer a join table invites.
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
    a.route,
    a.waypoints,
    a.intentions,
    a.note,
    a.place_name,
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

-- Lifetime totals for one member, plus their follow counts.
--
-- `follow_counts` is folded in here rather than standing alone: a profile reads
-- both together and there is no screen that wants one without the other.
--
-- `streak_days` is the run of consecutive calendar days, ending today or
-- yesterday, with at least one walk. Yesterday counts so a streak is not
-- reported broken before the walker has been out today.
-- TODO: timezone-aware. Days are bucketed in UTC, so a walk logged late at
-- night in Manila (UTC+8) lands on the next UTC day. Correcting this needs a
-- per-member timezone on `profiles`; until there is one, UTC is the limitation
-- we name rather than a correctness we pretend to.
create function public.member_stats(target uuid)
returns table (
  total_distance_meters  double precision,
  total_duration_seconds bigint,
  activity_count         integer,
  intention_count        integer,
  streak_days            integer,
  follower_count         integer,
  following_count        integer
)
language sql
stable
as $$
  with mine as (
    select a.started_at, a.distance_meters, a.duration_seconds, a.intentions
    from public.activities a
    where a.user_id = target
  ),
  totals as (
    select
      coalesce(sum(m.distance_meters), 0)::double precision as total_distance_meters,
      coalesce(sum(m.duration_seconds), 0)::bigint          as total_duration_seconds,
      count(*)::int                                         as activity_count,
      -- A row whose `intentions` is not an array counts as none, rather than
      -- erroring the whole profile.
      coalesce(
        sum(
          case when jsonb_typeof(m.intentions) = 'array'
               then jsonb_array_length(m.intentions)
               else 0 end
        ),
        0
      )::int as intention_count
    from mine m
  ),
  days as (
    select distinct (m.started_at at time zone 'utc')::date as d
    from mine m
    where (m.started_at at time zone 'utc')::date <= (now() at time zone 'utc')::date
  ),
  -- Gaps and islands: within a run of consecutive days, `d - rank` is constant.
  islands as (
    select d, d - (row_number() over (order by d desc))::int as grp
    from days
  ),
  streak as (
    select (
      select count(*)::int
      from islands i
      where i.grp = (select grp from islands order by d desc limit 1)
        and (select max(d) from islands) >= (now() at time zone 'utc')::date - 1
    ) as streak_days
  ),
  graph as (
    select
      (select count(*) from public.follows f where f.followee_id = target)::int as follower_count,
      (select count(*) from public.follows f where f.follower_id = target)::int as following_count
  )
  select
    t.total_distance_meters,
    t.total_duration_seconds,
    t.activity_count,
    t.intention_count,
    coalesce(s.streak_days, 0),
    g.follower_count,
    g.following_count
  from totals t, streak s, graph g;
$$;

grant execute on function public.feed_for(uuid, int, timestamptz) to authenticated;
grant execute on function public.activities_for(uuid, uuid, text, int) to authenticated;
grant execute on function public.activity_detail(uuid, uuid) to authenticated;
grant execute on function public.member_stats(uuid) to authenticated;
