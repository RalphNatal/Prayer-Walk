-- Recorded activities.
--
-- Route, waypoints and intentions are JSONB on the row rather than child
-- tables: a tracker always reads them together with the activity and never
-- queries into them. Normalising — or moving the route to PostGIS — is the
-- upgrade path if spatial queries are ever needed.

create table if not exists public.activities (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles(id) on delete cascade,
  type                  text not null check (type in ('walk','run','hike','cycle')),
  title                 text not null default '',
  started_at            timestamptz not null,
  duration_seconds      integer not null default 0,
  distance_meters       double precision not null default 0,
  elevation_gain_meters double precision not null default 0,
  route                 jsonb not null default '[]'::jsonb,  -- [[lat,lng], ...]
  waypoints             jsonb not null default '[]'::jsonb,  -- [{lat,lng,kind,label,note,elapsed_seconds}]
  intentions            jsonb not null default '[]'::jsonb,  -- [{text,category}]
  note                  text not null default '',
  created_at            timestamptz not null default now()
);

alter table public.activities enable row level security;

create index if not exists activities_user_started_idx
  on public.activities (user_id, started_at desc);

-- Readable by any authenticated user (supports viewing profiles now, feed later).
create policy "Activities readable by authenticated users"
  on public.activities for select to authenticated using (true);

-- Owners manage their own.
create policy "Users insert own activities"
  on public.activities for insert to authenticated with check (auth.uid() = user_id);
create policy "Users update own activities"
  on public.activities for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users delete own activities"
  on public.activities for delete to authenticated using (auth.uid() = user_id);
