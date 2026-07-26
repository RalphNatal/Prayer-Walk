-- Member-editable profile fields.
--
-- `profiles` already carries the server-provisioned identity (id, full_name,
-- avatar_url, role, created_at). This adds the four fields the person edits
-- themselves on Edit profile.
--
-- No new policies: "Users can update own profile" (auth.uid() = id) already
-- covers these columns, and the self-promotion trigger still guards `role`.
-- `status` is deliberately left out of the app's update path — it is an
-- admin/moderation field, not a member-editable one.

alter table public.profiles
  add column if not exists handle text unique,
  add column if not exists bio    text not null default '',
  add column if not exists parish text not null default '',
  add column if not exists status text not null default 'active'
    check (status in ('active','suspended'));
