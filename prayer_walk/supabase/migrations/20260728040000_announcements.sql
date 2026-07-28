-- Broadcasts from the console to the membership.
--
-- `recipient_count` is written once, at send time, and never recomputed. It is
-- a record of how many people this actually went to on the day — not a live
-- count that quietly grows as members join. "Sent to 42 people" has to keep
-- meaning what it meant when it was sent.
--
-- `sent_by_name`, like `devotionals.author_name`, is a byline rather than a
-- join: the announcement keeps the name of whoever sent it even after that
-- account is gone.

create table if not exists public.announcements (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  body            text not null default '',
  audience        text not null default 'everyone'
                    check (audience in ('everyone','activeMembers','admins')),
  sent_at         timestamptz not null default now(),
  sent_by         uuid references public.profiles(id) on delete set null,
  sent_by_name    text not null default '',
  recipient_count integer not null default 0
);

create index if not exists announcements_sent_at_idx
  on public.announcements (sent_at desc);

alter table public.announcements enable row level security;

drop policy if exists "Admins send announcements" on public.announcements;
create policy "Admins send announcements"
  on public.announcements for insert to authenticated
  with check (public.is_admin(auth.uid()));

drop policy if exists "Admins read all announcements" on public.announcements;
create policy "Admins read all announcements"
  on public.announcements for select to authenticated
  using (public.is_admin(auth.uid()));

-- A member reads what was addressed to them, and only that. The audience is
-- resolved against the reader's own row, so a suspended member does not see an
-- 'activeMembers' broadcast and an ordinary member never sees an admins-only
-- one — the addressing is enforced here, not by whichever screen is listing.
drop policy if exists "Members read announcements addressed to them"
  on public.announcements;
create policy "Members read announcements addressed to them"
  on public.announcements for select to authenticated
  using (
    audience = 'everyone'
    or (
      audience = 'activeMembers'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.status = 'active'
      )
    )
  );
