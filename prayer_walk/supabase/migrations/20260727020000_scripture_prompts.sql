-- Scripture and short prayers surfaced while a walk is being recorded.
--
-- The in-motion counterpart to `devotionals`: the same admin-curated shape,
-- but one glance or one spoken breath long rather than a reader page. Each one
-- delivered on a walk is written back onto the activity as an ordinary
-- waypoint (kind `scripture`), so nothing here changes the `activities` shape.
--
-- `translation` exists so a licensed translation can be added later without a
-- migration. Everything seeded today is public domain — see the seed file.

create table if not exists public.scripture_prompts (
  id           uuid primary key default gen_random_uuid(),
  reference    text not null,                       -- 'Psalm 121:1-2'
  body         text not null,                       -- the verse or prayer text
  translation  text not null default 'WEB',         -- public domain unless licensed
  kind         text not null default 'scripture'
                 check (kind in ('scripture','prayer')),
  category     text not null default 'stillness',   -- mirrors DevotionalCategory values
  is_published boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists scripture_prompts_published_idx
  on public.scripture_prompts (is_published, category);

alter table public.scripture_prompts enable row level security;

-- Everyone signed in reads published prompts; only admins curate.
create policy "Published prompts readable by authenticated"
  on public.scripture_prompts for select to authenticated
  using (is_published);

create policy "Admins manage prompts"
  on public.scripture_prompts for all to authenticated
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.role = 'admin'));
