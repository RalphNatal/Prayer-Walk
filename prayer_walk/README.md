# Prayer Walk

A Flutter app for recording walks, runs, hikes and rides as prayer — with a
member experience and an admin console, gated by a real role.

Authentication is **Supabase** (native Google + email/password). Which shell you
land in — member or admin — is driven by your `profiles.role`, enforced
server-side by RLS and a trigger. There is no Firebase in this project.

## Running the app

All runs need the environment file, passed with `--dart-define-from-file`:

```bash
# 1. Create your local env from the template and fill it in (see below).
cp env.example.json env.json

# 2. Run on a connected device / emulator.
flutter run --dart-define-from-file=env.json
```

`env.json` is **git-ignored** — never commit it. `env.example.json` is the
committed template with empty placeholders.

### Picking a device

List what's attached, then target one with `-d`:

```bash
flutter devices                              # connected devices + their ids
flutter emulators                            # installed Android emulators
flutter emulators --launch Pixel_9_Pro_XL    # boot one (id from the list above)
flutter run -d emulator-5554 --dart-define-from-file=env.json
```

With no `-d` and several devices attached (a desktop and a browser always
count), Flutter prompts you to choose. **Boot the Android emulator first** so it
is a candidate — otherwise Flutter may fall back to a browser/desktop target.

### Running from VS Code (F5)

`.vscode/launch.json` (at the repository root) defines **Prayer Walk (Android
emulator)**, **(Android — release)**, and **(iOS)**. Select one in the Run and
Debug panel and press **F5** — each already forwards
`--dart-define-from-file env.json`, so no manual flags are needed. Pick the
Android emulator as the active device in the status bar first; the configs do
not pin a device id. Do **not** add or run a web/Edge target — native Google
sign-in is mobile-only, and a web launch is what makes the app open a blank
Edge tab instead of the emulator.

> **Google sign-in needs Google Play Services.** Use an emulator system image
> that includes the Play Store / Play Services, and sign into a Google account
> on it once. On a bare AOSP image, or with no account added, the app still
> launches but native Google sign-in will fail.

### What goes in `env.json`

| Key | Where to find it | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | Supabase → Settings → API | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase → Settings → API | The publishable/anon key. Safe in a client; **not** the `service_role` key. |
| `GOOGLE_WEB_CLIENT_ID` | Google Cloud → the **Web** OAuth client | Used on Android as `serverClientId`, and registered in Supabase → Auth → Google (Client ID + Authorized Client IDs). |
| `GOOGLE_IOS_CLIENT_ID` | Google Cloud → the **iOS** OAuth client | Used on iOS as `clientId`. Its **reversed** form is the iOS URL scheme (see below). |

The Google **Web client secret** and the Supabase **service_role** key are never
used by the app and must not go in `env.json`.

### One value that can't live in `env.json`

The iOS URL scheme is the **reversed iOS client ID** and must be hardcoded in
`ios/Runner/Info.plist`. Replace the placeholder
`com.googleusercontent.apps.YOUR_REVERSED_IOS_CLIENT_ID` with your value —
e.g. an iOS client ID of `1234567890-abc.apps.googleusercontent.com` becomes
`com.googleusercontent.apps.1234567890-abc`.

## Bundle identifier

Both platforms use **`com.calledpresentations.prayer_walk`**. This must match
exactly what is registered in Google Cloud (the Android package name + iOS bundle
ID) and the Supabase redirect URLs. The Supabase deep-link redirect is
`com.calledpresentations.prayer_walk://login-callback` (Android intent-filter +
iOS URL scheme).

> The identifier is baked into several places that must stay in sync: Android
> `namespace` + `applicationId` (`android/app/build.gradle.kts`) plus the Kotlin
> source folder and its `package` declaration; iOS `PRODUCT_BUNDLE_IDENTIFIER`
> (`ios/Runner.xcodeproj/project.pbxproj`, all configs); the deep-link scheme on
> both platforms; and the registration in Google Cloud + Supabase. Change them
> together.

## Database

Schema lives in `supabase/migrations/`, oldest first. Apply a new one by pasting
it into the Supabase SQL editor (or `supabase db push` if you have the CLI
linked). They are written to be re-runnable.

| Migration | What it adds |
| --- | --- |
| `20260725000000_profiles_retro_captured` | `profiles`, and the signup trigger behind it. |
| `20260726000000_profiles_member_fields` | `handle`, `bio`, `parish`, `status` on `profiles`. |
| `20260726010000_activities` | Recorded walks, with route/waypoints/intentions as JSONB. |
| `20260727000000_activity_place_name` | `place_name` on `activities`. |
| `20260727010000_social_graph` | `follows`, `encouragements`, `comments`; the `feed_for` / `activities_for` / `activity_detail` / `member_stats` read functions. |
| `20260727020000_scripture_prompts` | Verses and short prayers delivered on a walk. |
| `20260728010000_admin_role_rules` | `is_admin()`, and who may administer whom. ⚠️ Changes two existing rules. |
| `20260728020000_devotionals` | The reader's content. |
| `20260728030000_moderation_reports` | Reporting an activity or a comment. |
| `20260728040000_announcements` | Parish broadcasts. |
| `20260728050000_admin_functions` | The console's reads, one round trip each. |
| `20260728060000_suspension_enforcement` | `is_active()`, and suspension made to mean something. |
| `20260728070000_devotional_translation` | `translation` on `devotionals`. |
| `20260728080000_visibility_zones_blocks` | `activities.visibility`, `privacy_zones`, `blocks`; the profile/follow/encourage/comment block rules. ⚠️ **Backfills every existing activity to `followers`.** |
| `20260728090000_visibility_rls_and_reads` | ⚠️ **Replaces the `activities` SELECT policy.** Server-side privacy-zone trimming, and the rewritten `feed_for` / `explore_feed` / `activities_for` / `activity_detail`. |
| `20260728100000_discovery` | `search_members`, `suggested_members`, and the prefix indexes behind them. |
| `20260728110000_scripture_submissions` | ⚠️ **Replaces the `scripture_prompts` SELECT policy.** Member submissions, the review queue, and the public-domain-only insert rule. |
| `20260729000000_scripture_deliveries` | Which passages a member has received, so verses stop repeating across walks. Owner-only, and never joined to anything public. |

Apply them in that order. Two need reading before they are run:

* **`20260728080000`** adds `visibility` to `activities` and backfills every
  existing row to `followers` — never to `public`. Those walks were recorded
  when the app made no promise either way, and turning that silence into
  "published to every account on the server" would widen the exposure of people
  who never asked for it. It changes no policy, so applying it on its own
  cannot break a running app.
* **`20260728090000`** drops `"Activities readable by authenticated users"`,
  which was `using (true)` — every signed-in account could read every route
  ever recorded. Apply it immediately after `20260728080000`. Afterwards the
  read surface narrows for everybody, and `member_stats` becomes viewer-scoped:
  another member's profile reports the totals of the walks *you may see*, which
  is the honest number rather than one derived from walks you cannot.

Every table has RLS on, and the member-facing read functions are `security
invoker` so the policies still apply inside them. The app only ever uses the
publishable key.

### What each viewer sees

| Walk is… | Owner | Follower | Non-follower | Blocked | Admin |
| --- | --- | --- | --- | --- | --- |
| `private` | full route | — | — | — | row only, trimmed |
| `followers` | full route | trimmed route | — | — | row only, trimmed |
| `public` | full route | trimmed route | trimmed route, and in Explore | — | row only, trimmed |
| by a suspended member | full route | — | — | — | row only, trimmed |

"Trimmed" means the points at either end of the trace that fall inside one of
the owner's privacy zones are gone before the response is serialised. Distance
and time stay whole and the card says so — `route_trimmed` on `activity_card`
is what makes it say it. Admins can read the row (moderation has to be able to
open what was reported, and the dashboard has to count) and are trimmed exactly
like a stranger.

### The one `security definer` function, and why

`activity_trace_for_viewer` is the exception, and it is the exception because
the rule would otherwise defeat itself. Trimming a route against its owner's
privacy zones means reading rows in `privacy_zones` that belong to somebody
else — correctly unreadable under RLS, because those rows say where the owner
lives. A security-invoker function would find no zones, trim nothing, and hand
over the full trace.

So it runs as its owner, and is written so the extra privilege can only ever
*remove* data: it takes an activity id rather than a route (so it cannot be fed
synthetic points and used as a proximity oracle), it re-asks
`pw_can_view_activity` itself because RLS is not applying inside it, and it
returns coordinates and a boolean — never a zone, a radius, a centre, or a
count of them. `pw_in_any_zone` has `EXECUTE` revoked from `authenticated`
outright and is reachable only from inside it.

Trimming both ends inward and leaving the middle whole is deliberate. Cutting a
hole out of the middle of a trace makes the map draw a straight line across the
gap whose two ends sit on the circle's edge, and a chord locates a centre far
more precisely than the honest curve running past it does.

`privacy_zones` is owner-only for read as well as write, with **no admin
exception**. An admin moderating a reported walk needs the walk; they do not
need to know where the walker lives.

### Verifying the visibility model

Three accounts — two ordinary members and one admin. The checks that matter are
done with a query rather than with the app: the UI hiding a walk is not the
test.

1. As member B, `select id, route from activities where user_id = '<A>'` for a
   `followers` walk of A's, with no follow between you. Zero rows.
2. Follow A and repeat. The row appears — and if A has a privacy zone over the
   start of that walk, the first coordinates are **absent from the response**,
   not merely undrawn.
3. As A, read the same walk. The route is whole and `route_trimmed` is false.
4. As B, `select * from privacy_zones`. Zero rows, always — including through
   any join you can construct.
5. Block B as A. B loses A's walks and A's profile; every follow between you is
   gone; neither can follow, encourage or comment on the other.
6. Suspend a member from the console. Their walks leave Discover, Explore,
   search and every other member's feed.
7. As B, `select * from explore_feed('<B>', 30, null)`. Public walks only, none
   of B's own, and nobody B already follows.

## Scripture licensing

Prayer Walk quotes scripture in three places: verses delivered on a walk
(`scripture_prompts`), passages quoted by devotionals (`devotionals`), and the
set bundled in the binary (`assets/scripture/prompts.json`). Every row carries a
`translation`, and a translation carries its terms — see
`lib/src/features/scripture/domain/bible_translation.dart`, which is the only
place a credit line or a per-quotation mark is written down.

### Which translations are supported

| Translation | Terms |
| --- | --- |
| **WEBBE** — World English Bible, British Edition | Public domain. No fee, no permission, no attribution obligation. The bundled offline set, the fallback, and the default. |
| **NLT** — New Living Translation | Copyrighted by Tyndale House Foundation. Quotable within the limits below, with a mandatory credit line. |

Adding another translation is a `const` in `bible_translation.dart` plus a line
in `BibleTranslation.values`. No display code changes.

### The NLT terms, verbatim

> Up to 500 verses may be quoted without express written permission, provided
> the quoted verses are not more than 25% of the work and no complete book of
> the Bible is quoted.

A credit line is mandatory. The full notice must appear in the app:

> Scripture quotations are taken from the Holy Bible, New Living Translation,
> copyright © 1996, 2004, 2015 by Tyndale House Foundation. Used by permission
> of Tyndale House Publishers, Carol Stream, Illinois 60188. All rights
> reserved.

For non-salable media the short form is acceptable, in which case the initials
**"(NLT)"** must appear at the end of each quotation.

Written permission is required for quotations beyond the limits, and for
commentary or Bible-reference works produced for commercial sale. Requests go to
**permission@tyndale.com**.

Prayer Walk uses the short form. The app appends `(NLT)` to every quotation
automatically — `BibleTranslation.attributed` is the only way quoted text
becomes displayable, and `test/scripture_attribution_test.dart` fails the build
if any screen reaches around it. The full notice appears in **Settings →
Scripture credits** whenever NLT content is loaded, and on the licence page
(`showLicensePage`).

**Open with Tyndale, unresolved:** whether express written permission is needed
for this use at all — the app is software rather than print or an eBook, and
Tyndale's requirements differ for commercial products — and whether any such
permission extends to text bundled inside the app binary. Until the second is
answered yes, `assets/scripture/prompts.json` stays WEBBE.

### Switching the app's translation

`SCRIPTURE_TRANSLATION` in `env.json` — `WEBBE` (default) or `NLT`:

```bash
flutter run --dart-define-from-file=env.json
```

Both editions can live in `scripture_prompts` at once, each row carrying its own
`translation`; this decides which one a walk draws from. No content is rewritten
and no rows are deleted. Prayers (`kind = 'prayer'`) quote nobody and are
delivered whatever it says. If the configured edition has no rows yet, the whole
library is delivered rather than nothing, and each verse still shows its own
credit.

The offline set is **not** switched by it. A device with no signal and no
synced cache reads the bundled WEBBE set and renders it with WEBBE attribution —
never the configured edition's mark.

### Where licensed text goes

Two templates, ready to fill in:

* `supabase/seed/scripture_prompts_nlt_seed.sql.template` — the walk library,
  restated as NLT rows. References, kinds, categories and sort order are
  populated; every body is `<<PASTE LICENSED NLT TEXT HERE>>`.
* `supabase/seed/devotionals_nlt_seed.sql.template` — updates the eight seeded
  devotionals' quoted passages in place, so the shelf stays one shelf.

Copy each to the same name without `.template`, paste the text, run it in the
Supabase SQL editor. Rows still holding a placeholder are skipped, so an
unfilled run does nothing. Both templates carry the terms above, the verse
count, and a SQL query that totals licensed verses across both tables against
the 500 ceiling. The admin scripture screen shows the same running total.

`supabase/seed/scripture_prompts_seed.sql` (WEBBE) is not replaced by any of
this. It stays as the fallback and the licence-free baseline.

> **NLT text is never committed by an AI assistant and never scraped.** It is
> pasted by the maintainer from a source they are licensed to use. Not typed
> from memory, not copied from an unlicensed site, not fetched from a Bible API,
> and not generated by a model. Unlicensed retrieval is the same violation as
> unlicensed pasting.

`20260728070000_devotional_translation.sql` adds `devotionals.translation` and
must be applied before the devotionals template will run.

### Member-contributed prompts, and the ceiling

A member can now propose a prompt from Settings → *Suggest a scripture prompt*.
The form is shaped around what a member can give: a reference, a theme, and a
line of their own about why this one. It is not shaped that way for tidiness.

An open submissions form is where a 500-verse ceiling gets crossed. A curated
admin set of about fifty NLT verses sits comfortably inside Tyndale's limit; a
parish enthusiastically pasting NLT passages would pass five hundred in a
season, nobody would be counting, and a manageable permission question would
have become genuine infringement at a scale nobody could reconstruct.

So the optional free-text field is **public-domain only**, and that is enforced
by the insert policy in `20260728110000_scripture_submissions.sql` rather than
requested politely by the form:

```sql
and upper(btrim(coalesce(translation, ''))) in ('', 'WEB', 'WEBBE')
```

A member submission therefore costs nothing against the ceiling. The only way
licensed text enters is an admin deliberately setting a translation on review —
and the submissions queue shows the running total against `kNltVerseCeiling`
before any decision is taken, with an approval that would cross it gated behind
a dialog naming the number it would reach.

There is no member `UPDATE` policy on `scripture_prompts` at all, so nothing can
publish itself: a submission arrives `pending`, is invisible to everyone but its
author and an admin, and reaches a walk only when an admin approves it. The
contributor's name travels with it from there — an approved prompt is credited
beside the same quotation that carries its translation mark.

**Current count: 0 of 500.** Everything in this repository is public domain —
41 WEBBE rows in `scripture_prompts_seed.sql` and eight devotionals, none of
them NLT — so a database seeded from it quotes no licensed verses at all. The
number moves only when the NLT templates above are filled in. It is a count of
what is in *your* database rather than what is in the repo, so read it off the
admin scripture screen or the submissions queue, both of which total it live
across `scripture_prompts` and `devotionals` together — Tyndale's limit is on
the work, not on one of its lists.

## Builds

```bash
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=env.json      # Android
flutter build ios --no-codesign --dart-define-from-file=env.json  # iOS (macOS)
```

On iOS, run `cd ios && pod install` once after fetching packages (macOS only).

## Platform setup notes

- **Android** — `minSdk 23` (Credential Manager requirement); INTERNET permission
  and the Supabase deep-link intent-filter are in the manifest; R8 keep rules for
  Credential Manager live in `android/app/proguard-rules.pro` and are wired into
  the `release` build type (release Google sign-in fails without them).
- **iOS** — URL schemes (reversed Google client ID + the Supabase deep link) are
  in `Info.plist`; deployment target is 13.0.
