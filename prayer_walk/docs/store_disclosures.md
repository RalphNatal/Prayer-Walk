# Store data-safety disclosures

> **Draft, from the code.** This maps what the app actually collects (per
> `docs/privacy_policy.md`, which this should stay consistent with) onto the
> two stores' disclosure forms. The category names below are the two stores'
> own vocabulary as of this writing — re-check the current wording in each
> console before submitting, since both stores revise their category lists
> periodically. Nothing here is legal advice; treat it as a first draft for
> whoever fills in the actual console forms.

## The one fact that simplifies both forms

**There is no advertising SDK and no analytics SDK in this app.** Checked
against `pubspec.yaml`: every dependency is either a Flutter/Dart core
package, a UI package (`flutter_map`, `image`, `flutter_tts`,
`audioplayers`), a device-capability package (`geolocator`, `pedometer`,
`permission_handler`, `image_picker`), or `supabase_flutter` /
`google_sign_in`. None of these report usage analytics or ad identifiers
anywhere. So for every data type below: **used for tracking across other
apps/websites: No**, and there is no "third-party advertising" purpose to
declare anywhere in either form.

## Data collected

| Data type | Collected | Linked to identity | Purpose | Optional | Google Play Data Safety category | Apple Privacy Nutrition Label category |
| --- | --- | --- | --- | --- | --- | --- |
| Precise location (route while recording) | Yes | Yes | App functionality (recording a walk's route) | No — required to record a walk; not required to use the rest of the app | Location → Precise location | Location → Precise Location |
| Background location | Yes | Yes | App functionality (a walk continues after the screen locks) | No, once you choose to record — but recording itself is optional | Location → Precise location (background) | Location → Precise Location |
| Profile photo | Yes, if added | Yes | App functionality / user-generated content (identifying yourself to other members) | Yes | Photos and videos | User Content → Photos or Videos |
| Profile fields (name, handle, bio, parish, pronouns, typed location, link) | Yes | Yes | App functionality, account management | Display name required; rest optional | Personal info → Name; App activity → Other user-generated content | Contact Info → Name; User Content → Other User Content |
| Comments and encouragements | Yes | Yes | App functionality / user-generated content | Yes, by choosing to write one | App activity → Other user-generated content | User Content → Other User Content |
| Scripture delivery history | Yes | Yes | App functionality (not repeating a passage you've recently read) | No — inherent to using the scripture feature | App activity → App interactions | User Content → Other User Content |
| Walk metadata (distance, duration, elevation, intentions, notes) | Yes | Yes | App functionality, and social content if shared | Sharing is optional; recording metadata is inherent to using the feature | App activity → App interactions | Fitness → Other Fitness Data |
| Approximate location for place name (Mapbox geocoding) | Yes, transient | Yes (tied to the walk being saved) | App functionality (a readable place name instead of coordinates) | No — automatic when a walk ends and Mapbox is configured | Location → Approximate location | Location → Coarse Location |
| Account credentials (email/password, or Google sign-in) | Yes | Yes | Account creation and authentication | You choose the method | Account info | Contact Info / Identifiers |

Every row above: **used for tracking: No. Shared with third parties for
their own purposes: No.** Data reaches Supabase (processor, storing app data
on the developer's behalf), Mapbox (processor, for map tiles and the
place-name lookup), and Google (only if you choose Google Sign-In, for
authentication) — all as service providers performing a function of the app,
not as recipients using the data for their own purposes.

## Data NOT collected

Worth stating explicitly on both forms, since their absence is a deliberate
design choice, not an oversight: no advertising identifier, no purchase
history (no in-app purchases exist), no health/fitness data beyond the walk
metadata above (no heart rate, no Apple Health / Google Fit integration), no
contacts access, no audio/microphone access, no browsing history.

## Google Play — Data Safety form notes

- **Data collection: Yes.**
- **Data sharing with third parties: No** (Supabase, Mapbox and Google are
  service providers, not third parties the data is "shared" with under
  Play's definition — but re-confirm this framing against Play's current
  guidance before submitting, since Play's own definition of "shared" has
  changed before).
- **Is all data encrypted in transit: Yes** (Supabase and Mapbox are both
  accessed over HTTPS).
- **Can users request data deletion: Yes** — in-app, Settings → Delete
  account (see `docs/privacy_policy.md`).
- Background location requires the separate declaration below.

## Apple — Privacy Nutrition Label notes

- Location, User Content, Contact Info, and Fitness data types apply, per
  the table above.
- **Data Used to Track You: None.**
- **Data Linked to You:** effectively everything in the table, since almost
  all of it is tied to your account.

---

## Background location justification (paste into Play Console)

Google Play requires a written justification for the
`ACCESS_BACKGROUND_LOCATION` permission, reviewed by a human, plus (per
current policy) a short demo video showing the feature. Draft copy below —
adjust to the console's current character limit and field wording before
submitting.

> **What the feature does:** Prayer Walk records a GPS route during a
> contemplative walk that the member explicitly starts. Members frequently
> keep their phone in a pocket or bag, or lock the screen, during a walk that
> can run well over an hour. Background location access lets the app keep
> recording the route during that time.
>
> **Why foreground-only location is not sufficient:** Android suspends
> foreground-only location updates when the app is backgrounded or the
> screen locks. Without background access, a walk longer than the time the
> screen stays on would record an incomplete or badly gapped route — exactly
> the failure mode the feature exists to avoid. The permission is requested
> only at the moment a member starts a recording, never at app launch, and
> only after foreground location has already been granted.
>
> **What the in-app disclosure says:** [see `location_service.dart`'s own
> rationale strings, and the two platform manifests —
> `AndroidManifest.xml`'s comments at the top of the location permission
> block, and `Info.plist`'s `NSLocationAlwaysAndWhenInUseUsageDescription`
> string, both already written in the member's own words, not legal
> language.] Recording — and background access — stops the moment the
> member taps Finish; location is never read outside an active recording.

**Before submitting:** Google requires a demo video showing the background
location feature in use (typically: start a recording, background the app
or lock the screen, show the walk still being tracked, return and finish
it). Record this on a real device against a build using the feature as
shipped. Play's review of a background-location declaration is manual and
can take longer than a standard review — budget time for it ahead of a
launch date, and expect at least one round of clarifying questions if the
justification text above is trimmed too far to fit the console's field.
