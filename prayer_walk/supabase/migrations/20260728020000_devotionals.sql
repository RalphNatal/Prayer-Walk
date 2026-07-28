-- Devotionals: the reader-length counterpart to `scripture_prompts`.
--
-- Same admin-curated shape as the prompt library, sized for a page rather than
-- a glance. `category` is checked against the *value names* of the Dart
-- `DevotionalCategory` enum, not its labels — the same convention
-- `scripture_prompts.category` already uses, so one theme means one thing on
-- both tables.
--
-- `author_name` is stored alongside `author_id` on purpose. It is a byline, not
-- a join: the name shown on a devotional is the name the person had when they
-- wrote it, and a devotional outlives the account that published it
-- (`on delete set null`).

create table if not exists public.devotionals (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  summary        text not null default '',
  body           text not null default '',
  scripture_ref  text not null default '',
  scripture_text text not null default '',
  category       text not null default 'morningLight'
                   check (category in (
                     'morningLight','gratitude','intercession',
                     'lament','stillness','scriptureWalk'
                   )),
  author_id      uuid references public.profiles(id) on delete set null,
  author_name    text not null default '',
  read_minutes   integer not null default 3,
  is_published   boolean not null default false,
  published_at   timestamptz,
  updated_at     timestamptz not null default now(),
  created_at     timestamptz not null default now()
);

-- The member shelf reads published-and-in-this-category; the admin list reads
-- everything. This index serves the first, which is the one on a hot path.
create index if not exists devotionals_published_category_idx
  on public.devotionals (is_published, category);

-- ------------------------------------------------------------ updated_at ---
--
-- Stamped by the database rather than trusted from the client: "updated
-- 2 minutes ago" on the admin list should mean the row changed, not that
-- somebody's clock said so.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists devotionals_touch_updated_at on public.devotionals;
create trigger devotionals_touch_updated_at
  before update on public.devotionals
  for each row execute function public.touch_updated_at();

-- -------------------------------------------------------------------- RLS ---

alter table public.devotionals enable row level security;

-- A member sees the shelf, and the shelf is what has been published. A draft is
-- invisible to them at the row level, not merely absent from a query — an
-- unpublished devotional must not be readable by guessing its id.
drop policy if exists "Published devotionals readable by authenticated"
  on public.devotionals;
create policy "Published devotionals readable by authenticated"
  on public.devotionals for select to authenticated
  using (is_published);

drop policy if exists "Admins manage devotionals" on public.devotionals;
create policy "Admins manage devotionals"
  on public.devotionals for all to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
