-- The console's reads, one round trip each.
--
-- Every function here is `security invoker` — RLS still applies inside them,
-- exactly as it does for the member-facing functions in the social-graph
-- migration. None of them is a way past a policy; each one is a way past N+1.
-- The dashboard was four queries and a per-row count, the members table one
-- count query per member, the moderation queue two lookups per report. That is
-- what these replace.
--
-- Each also guards explicitly on the caller being an admin and raises 42501
-- otherwise, so a non-admin calling one of these directly with their own
-- anon-key session is refused by the database rather than by a hidden button.
-- The guard is belt and braces over RLS, not a substitute for it.

-- --------------------------------------------------------- admin_metrics ---
--
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
        'parish', p.parish,
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

-- --------------------------------------------------------- admin_members ---
--
-- The members table with its activity counts already attached. The column names
-- match `profileColumns` so the app's one row→UserProfile mapper reads these
-- rows like any other.
--
-- Nulls mean "no filter". An empty search string means the same, so the screen
-- can send its controller state through unmodified.

create or replace function public.admin_members(
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
  parish         text,
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
    p.parish,
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
      or coalesce(p.parish, '')    ilike '%' || btrim(search) || '%'
    )
    and (role_filter is null or p.role = role_filter)
    and (status_filter is null or p.status = status_filter)
  order by coalesce(nullif(btrim(p.full_name), ''), 'Walker'), p.created_at
  limit greatest(1, least(coalesce(limit_count, 200), 500));
end;
$$;

-- --------------------------------------------------------- admin_reports ---
--
-- The queue, with each report's target already resolved to an excerpt and an
-- author name. `target_id` points at an activity *or* a comment and has no
-- foreign key to lean on, so both are tried and whichever exists wins.
--
-- A target that has since been deleted yields nulls here rather than dropping
-- the report. That is the case the console has to render as "content removed" —
-- the report still happened, and an admin still has to close it.

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
    coalesce(act.excerpt, cmt.excerpt),
    coalesce(act.author_name, cmt.author_name),
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
  where status_filter is null or r.status = status_filter
  order by r.created_at desc;
end;
$$;

-- -------------------------------------------------- admin_resolve_report ---
--
-- Closing a report and reading back what the queue shows are the same shape, so
-- they are the same query. Without this the console would write the status,
-- then re-read the whole queue to find out what it had just written.
--
-- `resolved_by` is taken from the session rather than from the caller: who
-- closed a report is a fact about the request, not a parameter of it.

create or replace function public.admin_resolve_report(
  report_id uuid,
  outcome   text
)
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
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'The admin console is for admins.' using errcode = '42501';
  end if;

  if outcome not in ('pending', 'resolved', 'dismissed') then
    raise exception 'Unknown report outcome: %', outcome using errcode = '22023';
  end if;

  update public.moderation_reports r
     set status      = outcome,
         -- Reopening a report clears the closure rather than leaving a stale
         -- "resolved by" on something that is open again.
         resolved_at = case when outcome = 'pending' then null else now() end,
         resolved_by = case when outcome = 'pending' then null else auth.uid() end
   where r.id = report_id;

  if not found then
    -- P0002 = no_data_found. A five-character SQLSTATE, unlike PostgREST's own
    -- PGRST codes, which Postgres will not accept here.
    raise exception 'That report is no longer there.' using errcode = 'P0002';
  end if;

  return query
  select * from public.admin_reports(null) ar where ar.id = report_id;
end;
$$;

-- --------------------------------------------------------- audience_size ---
--
-- What an announcement is about to reach, counted the same way the audience is
-- later resolved by the announcements read policy — so the number on the
-- confirm dialog is the number of people who will actually see it.

create or replace function public.audience_size(audience text)
returns integer
language plpgsql
stable
as $$
declare
  n integer;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'The admin console is for admins.' using errcode = '42501';
  end if;

  select count(*)::int into n
  from public.profiles p
  where case audience
          when 'everyone'      then true
          when 'activeMembers' then p.status = 'active'
          when 'admins'        then p.role = 'admin'
          else false
        end;

  return coalesce(n, 0);
end;
$$;

grant execute on function public.admin_metrics() to authenticated;
grant execute on function public.admin_members(text, text, text, int) to authenticated;
grant execute on function public.admin_reports(text) to authenticated;
grant execute on function public.admin_resolve_report(uuid, text) to authenticated;
grant execute on function public.audience_size(text) to authenticated;
