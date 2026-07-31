-- Profile photos: the `avatars` bucket, its policies, and the end of the
-- borrowed Google URL.
--
-- Three things happen here, and they belong in one file because the third is
-- only safe once the first two exist:
--
--   1. an `avatars` bucket, keyed by member id so ownership is derivable from
--      the object path alone;
--   2. storage policies that let any signed-in person read an avatar and let a
--      member write only inside their own folder;
--   3. `handle_new_user()` stops copying Google's avatar URL, and the URLs it
--      already copied are cleared.
--
-- Note on privileges: the policies below are on `storage.objects`, which is
-- owned by `supabase_storage_admin`. Run this from the dashboard SQL editor (it
-- executes as `postgres`, which is a member of that role) or with the service
-- role. A migration applied as an ordinary user will fail on the `create
-- policy` statements, not on the bucket insert — if that happens, nothing is
-- half-applied, because it is all one transaction.

-- ---------------------------------------------------------------- bucket ---
--
-- Public, deliberately. An avatar is rendered by `Image.network` in the feed,
-- on comments, in discovery and in the admin console — twenty of them on one
-- screen — and the alternative is a signed URL per object per render, which
-- means an extra round trip before a byline can draw, no HTTP caching worth the
-- name, and a link that stops working while the screen is still open. The
-- objects are named with a v4 uuid, so a URL is unguessable; it is simply not
-- secret once shared. That is the normal trade for avatars and it is the one
-- the app is written against.
--
-- If auth-gated reads are ever wanted instead: flip `public` to false here and
-- change `SupabaseProfileRepository.uploadAvatar` to hand back a signed URL —
-- that one method is the only place a URL is minted.
--
-- The limits are a server-side backstop, not the primary control. The client
-- resizes to 512px and encodes JPEG at roughly 40-80 KB (see
-- `avatar_image.dart`); these numbers only decide what a *broken or hostile*
-- client is allowed to leave behind. JPEG is the only type because the client
-- pipeline always encodes JPEG — anything else arriving here did not come from
-- this app.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 524288, array['image/jpeg'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- -------------------------------------------------------------- policies ---
--
-- Objects are keyed `avatars/{user_id}/{uuid}.jpg`, so `foldername(name)[1]` is
-- the owning member's id and every write policy is the same one comparison.
-- Ownership is in the path rather than in `storage.objects.owner` on purpose:
-- the path is what the app constructs and what these policies read, so there is
-- no second source of truth to disagree with the first.

-- Members-only app, and avatars appear beside names all over it. Matches
-- "Profiles readable by authenticated" on the table itself — a member whose
-- name you can see is a member whose face you can see.
--
-- On a public bucket this governs the authenticated object path; the public
-- path is served without RLS by design (see the bucket note above). It is
-- written out anyway so that flipping the bucket to private is a one-word
-- change here rather than a new policy to get right under pressure.
drop policy if exists "Avatars readable by authenticated" on storage.objects;
create policy "Avatars readable by authenticated"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');

-- Your own folder, and only your own — the storage half of "Users can update
-- own profile". Without this a member could write an object into someone
-- else's folder and then, because `profiles.avatar_url` is just text, never
-- need to touch their row to do it.
drop policy if exists "Members upload their own avatar" on storage.objects;
create policy "Members upload their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- `upsert: true` on a replaced photo lands here rather than on insert. Both
-- halves are checked: `using` decides which rows may be targeted, `with check`
-- decides what they may become — without the second, an update could rename an
-- object out of the owner's folder.
drop policy if exists "Members replace their own avatar" on storage.objects;
create policy "Members replace their own avatar"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Needed by both Remove photo and the delete-the-old-object step of a replace.
-- Scoped the same way, so a member sweeping their own folder cannot sweep
-- anyone else's.
drop policy if exists "Members delete their own avatar" on storage.objects;
create policy "Members delete their own avatar"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ------------------------------------------------- signup no longer borrows ---
--
-- The old trigger copied `raw_user_meta_data ->> 'avatar_url'` — a
-- `googleusercontent.com` URL — into `profiles.avatar_url` at signup. It is
-- dropped from the insert here for two reasons, in order of weight:
--
--   1. Every render of that URL is a request from a member's device to Google.
--      A feed of twenty cards is twenty pings to a third party, from people who
--      chose this app partly because it trims their walking routes. The app
--      does not get to argue for privacy on one screen and leak on another.
--   2. It is a URL nobody here controls. It rots when the account changes its
--      photo, and it cannot be swept when a member removes their photo, because
--      there is no object of ours to delete.
--
-- What is lost is real and small: someone who signs in with Google no longer
-- arrives with a photo already set. They see their initials — the same as an
-- email/password member — until they upload one, which is now a thing they can
-- actually do. The alternative, fetching Google's image once and re-hosting it,
-- was considered and rejected: it spends a network round trip and a silent
-- failure mode on first sign-in to copy a photo the member never chose to put
-- in this app.
--
-- The result is an invariant worth having: `profiles.avatar_url` is either null
-- or an object in our own `avatars` bucket. Nothing else. That is what lets the
-- replace path delete the previous object without first asking where it lives.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      ''
    )
  )
  -- A retried signup, or a row restored by hand, must not fail the sign-in.
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The URLs the old trigger already wrote. Clearing them is invisible to every
-- member: until this phase `UserProfile` had no `avatarUrl` at all, so not one
-- of these was ever drawn on a screen. They are cleared rather than left alone
-- precisely because the app starts rendering `avatar_url` in this same change —
-- leaving them would silently turn on the third-party fetch that reason (1)
-- above exists to prevent.
--
-- Matched on the bucket path, so an avatar uploaded through the new path
-- survives a re-run of this file.
update public.profiles
   set avatar_url = null
 where avatar_url is not null
   and avatar_url not like '%/storage/v1/object/public/avatars/%';
