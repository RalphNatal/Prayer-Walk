-- What a member flags, and what an admin does about it.
--
-- `target_id` has no foreign key, deliberately: it points at either an
-- `activities` row or a `comments` row, and Postgres has no way to say "one of
-- these two". The cost of that choice is that the target can vanish underneath
-- a report — the walk gets deleted, the comment is removed — so every read
-- resolves the excerpt at read time and every surface has to render a missing
-- target as "content removed" rather than erroring or dropping the row.
-- `admin_reports()` (next migration) is where that resolution happens.

create table if not exists public.moderation_reports (
  id          uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('activity','comment')),
  target_id   uuid not null,
  reason      text not null default '',
  reported_by uuid not null references public.profiles(id) on delete cascade,
  status      text not null default 'pending'
                check (status in ('pending','resolved','dismissed')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,

  -- One report per person per target. A second tap on Report is a 23505, not a
  -- second row in the queue — which is what keeps one annoyed member from
  -- burying everything else an admin needs to see.
  unique (target_type, target_id, reported_by)
);

-- The queue's own ordering: pending first, newest at the top.
create index if not exists moderation_reports_status_created_idx
  on public.moderation_reports (status, created_at desc);

alter table public.moderation_reports enable row level security;

-- A member files a report as themselves and can see the ones they filed.
-- They cannot see anyone else's — a report is not a public accusation.
drop policy if exists "Members file own reports" on public.moderation_reports;
create policy "Members file own reports"
  on public.moderation_reports for insert to authenticated
  with check (auth.uid() = reported_by);

drop policy if exists "Members read own reports" on public.moderation_reports;
create policy "Members read own reports"
  on public.moderation_reports for select to authenticated
  using (auth.uid() = reported_by);

drop policy if exists "Admins read all reports" on public.moderation_reports;
create policy "Admins read all reports"
  on public.moderation_reports for select to authenticated
  using (public.is_admin(auth.uid()));

-- Resolving and dismissing. Admins only, and only ever an update — a report is
-- part of the record of what was decided, so nothing here deletes one.
drop policy if exists "Admins resolve reports" on public.moderation_reports;
create policy "Admins resolve reports"
  on public.moderation_reports for update to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
