-- Where a walk happened, in words: "Antipolo", "Kreuzberg", "Mile End".
--
-- Resolved once by reverse geocoding when the activity is saved, then stored,
-- so reading a walk never costs a geocoding request. Nullable and without a
-- default on purpose — it is null for every activity recorded before this
-- column existed, for walks logged without a route, and whenever the lookup
-- failed or the app had no map token. Readers must treat null as ordinary.
--
-- No backfill: the coordinates are on the row, but geocoding every historical
-- activity would be a bulk spend against the maps quota to fill in a caption.
-- Old walks simply keep their plain titles.

alter table public.activities
  add column if not exists place_name text;

comment on column public.activities.place_name is
  'Reverse-geocoded place name for the route origin. Null is ordinary: no route, lookup failed, or recorded before 2026-07-27.';
