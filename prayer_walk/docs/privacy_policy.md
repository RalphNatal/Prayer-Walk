# Prayer Walk — Privacy Policy

**Last updated:** 29 September 2026

## Who this is

Prayer Walk is an app for recording contemplative walks — prayer, scripture,
gratitude — and, if you choose, sharing them with people who follow you or
with the wider community of members. This policy explains what the app
collects, why, where it lives, who can see it, and how to have it deleted.

Prayer Walk is published by CALLED Presentations.

**Contact:** calledpresentations@gmail.com

## What is collected, and why

### Your walking route (precise, and background, location)

While you are recording a walk, the app reads your device's precise GPS
location continuously — including while your screen is locked or the app is
in the background — so that a walk you started is still a complete walk when
you finish it. Location is **only read between tapping Start and tapping
Finish**; it is never read at any other time, including while the app is open
but no walk is being recorded.

- On iOS, background recording uses the "Always" location permission and a
  background location mode, requested only at the moment you start a
  recording.
- On Android, foreground location is requested first; background location
  ("Allow all the time") is requested separately, also only when you start a
  recording.
- If your device reports a reduced-accuracy location, the app asks once per
  session for temporary full accuracy, because a trimmed or approximate trace
  does not represent the walk you actually took.

The recorded route — a list of coordinates, your distance, duration, and
elevation gain — is stored with the walk and is subject to the visibility
setting described below.

**Privacy zones.** You can mark places (home, a school gate, anywhere) as a
privacy zone. When anyone other than you views one of your walks, the server
itself removes any points at the start or end of the route that fall inside a
zone — before the coordinates ever leave the database. This is not a
client-side filter that a modified app could bypass; it happens in the
database query that serves the walk to another person. Your privacy zones
themselves are visible to nobody but you — not other members, not through any
public view, not to an administrator.

### Your profile photo

If you add a profile photo, it is resized, cropped, and re-encoded on your
device before it is uploaded — and **every EXIF tag, including GPS location
metadata a camera writes into a photo, is stripped before the file leaves
your device.** A photo taken at home does not carry your home's coordinates
into your profile.

### Profile information you type in

Display name, handle (@username), a short bio, your parish or community,
pronouns, a typed location ("Antipolo, Rizal" — a place you type, never a
GPS reading), and a personal or parish link. All of these are optional except
your display name, and all are visible to any other signed-in member — the
app tells you this on the edit screen itself.

### Content you write

Comments on other members' walks, and "encouragements" (a lightweight
acknowledgement, like a blessing) on a walk. Both are tied to your account
and visible to anyone who can see the walk they're attached to.

### Scripture delivered to you

Which scripture passages and prayers have been delivered to you on past
walks, so the app can avoid repeating a passage you've recently read. This
history is functional, not social — it is not shown to other members.

### Approximate location for a place name

When a walk ends, the app makes one lookup against Mapbox's geocoding service
to turn your end coordinate into a readable place name ("Antipolo" rather
than a string of numbers). Only a neighbourhood-to-town-level name is
requested — never a street address — and the coordinate sent is rounded to
roughly a 100-metre grid before the request is made.

### What is not collected

There is no advertising SDK and no analytics SDK anywhere in this app. There
is no tracking of you across other apps or websites, and no data is sold or
rented to anyone.

## Where your data is stored

All of the data described above — your profile, your walks, your comments,
your scripture history — is stored in a Supabase project hosted in the
United States (US West, Northern California), using Supabase (Supabase, Inc.)
as the database and file storage provider. Your profile photo is stored in
Supabase's file storage, in a bucket keyed to your account.

## Who can see what

Every walk has a visibility setting you choose, per walk:

| Setting | Who sees it |
| --- | --- |
| **Only me** | Nobody but you. Still counted in your own history and totals. |
| **Followers** (the default) | People who follow you. |
| **Everyone** | Any signed-in member, including people you've never met — the only setting that appears in Discovery. |

Nothing widens automatically: a walk keeps the visibility it was recorded
with unless you change it, and past walks are never widened by an app
update.

**Blocking.** If you block someone, neither of you can see the other's walks
or profile, follow each other, or interact on a walk — and if either of you
followed the other, that follow ends immediately.

**Administrators.** A small number of designated administrators can access
moderation reports and take action on reported content (suspending an
account, removing content) as part of keeping the community safe. Your
privacy zones are never visible to an administrator, and an administrator
does not have a general ability to browse private ("Only me") walks.

## Third parties actually used

Only the services this app actually integrates with, nothing more:

- **Supabase** — database, authentication, and file storage.
- **Google Sign-In** — if you choose to sign in with Google, Google handles
  that authentication; the app never sees or stores your Google password.
- **Mapbox** — draws the map you see when reviewing a route, and provides the
  one-time place-name lookup described above. Loading a map tile is, like any
  map in any app, a request from your device to Mapbox for the tiles covering
  the area you're viewing.
- **OpenStreetMap** — the map's underlying data, and the fallback tile source
  if the app has no Mapbox access configured.

## Children's data

Prayer Walk is rated 13+ on the App Store and is not intended for children
under 13. We do not knowingly collect personal information from anyone under
13.

If we become aware that a member is under 13, we will delete their account
and the data associated with it. If you believe a child under 13 has created
an account, contact us at calledpresentations@gmail.com and we will remove it.

## How long data is kept

Your data is kept for as long as your account exists. There is no automatic
expiry on walks, comments, or scripture history. You control retention
directly by deleting individual content (a comment, a walk) or your entire
account, described next.

## Deleting your account and your data

Settings → Delete account, inside the app, at any time. This is a permanent,
in-app action — no email or support request is required.

Deleting your account removes: your profile and your sign-in, every walk you
recorded, your follows and followers, anyone you blocked, every comment and
encouragement you left (and comments left on your walks), your privacy
zones, your scripture delivery history, and your profile photo.

A devotional or announcement you published for your parish keeps its byline
text — the way a newspaper article outlives its author leaving the paper —
but the moment your account is deleted, that content is no longer linked to
you in any way; nothing about it can be traced back to your account.

The app also offers a data export (a JSON copy of your profile, walks,
comments, and encouragements) from the same screen, so you can keep a copy
before you delete.

## Changes to this policy

When this policy changes, we update the "Last updated" date at the top of
this page. If a change materially affects how your data is collected, used,
or shared, we will also show a notice inside the app before the change takes
effect, so you see it without having to check this page.

## Contact

Questions about this policy, or requests about your data:

**CALLED Presentations**
Email: calledpresentations@gmail.com
Web: https://calledpresentations.com