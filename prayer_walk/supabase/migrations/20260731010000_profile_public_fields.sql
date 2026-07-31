-- Three more member-editable fields: pronouns, location, links.
--
-- No new policies, for the same reason as
-- `20260726000000_profiles_member_fields.sql`: "Users can update own profile"
-- (auth.uid() = id) already covers every column on this table, and `role` and
-- `status` stay guarded by the self-promotion trigger and the admin policy.
-- Adding columns does not widen who may write the row.
--
-- All three are public. Everything on `profiles` is readable by any signed-in
-- member — that is what the feed byline and discovery are built on — so there
-- is no such thing as a private field here, and the edit form says so in as
-- many words rather than letting someone assume otherwise.

alter table public.profiles
  -- Short by design: "she/her", "they/them". A sentence belongs in the bio.
  add column if not exists pronouns text not null default ''
    check (char_length(pronouns) <= 40),

  -- City-level, free text, and deliberately not coordinates. This app already
  -- trims the ends off recorded routes so a walk does not publish a doorstep;
  -- a profile field that captured a precise position would hand back exactly
  -- what that trimming exists to withhold. It is a label a member types, and
  -- nothing reads it as a place.
  add column if not exists location text not null default ''
    check (char_length(location) <= 80),

  -- One URL — a personal page, a parish page. Named in the plural because that
  -- is the field members are promised; it holds exactly one, and a second one
  -- would want its own table rather than a longer string.
  --
  -- The scheme is validated on the way in (`profileLink`) and again on the way
  -- out, because a column is forever and a client is a version. Rendered as
  -- text or opened in the system browser — never in an in-app webview, which
  -- would put a member-supplied page inside the app's own session.
  add column if not exists links text not null default ''
    check (char_length(links) <= 200);
