# Play Console submission checklist

> Everything below is what happens **in Play Console**, after a signed release
> build exists. It consolidates `docs/store_disclosures.md`,
> `docs/background_tracking.md` and `docs/privacy_policy.md` into the order
> Play Console actually asks for them. Nothing here is legal advice — the
> privacy policy remains a draft for review, and the Data Safety answers
> should be re-checked against Play's current form wording before submitting,
> since both drift over time.

## 0. Before you start

- [ ] A signed release AAB exists (`flutter build appbundle --release
      --dart-define-from-file=env.json`) and was smoke-tested per
      `docs/release_smoke_test.md`.
- [ ] The upload keystore (`android/prayer-walk-upload.jks`) is backed up
      somewhere outside this repo — a password manager or encrypted backup.
      It is git-ignored on purpose; losing it with no backup means a support
      round-trip with Google to recover upload access.
- [ ] The privacy policy is hosted somewhere with a stable public URL (GitHub
      Pages, a plain static host, etc.) — Play Console requires a live URL,
      not a repo path. `docs/privacy_policy.md` is the source; it needs
      review before it's treated as final, not just publishing.

## 1. Store listing

| Field | Source / notes |
| --- | --- |
| App name | Prayer Walk |
| Short description (80 chars) | Draft, e.g. "Record a prayer walk, receive scripture, and share it with your church." — trim to fit and pick final wording. |
| Full description | Draft from the app's own feature set: route recording, step- or distance-paced scripture delivery, a feed for sharing walks with other members, devotionals. Write this fresh — nothing in the repo is pre-written store copy. |
| App category | Lifestyle, or Health & Fitness — pick based on how the walk-recording vs. devotional/social balance should read to a browsing user. |
| Contact email | The developer account's support address. |
| Privacy policy URL | The hosted URL from step 0. |
| Screenshots / feature graphic | Not in the repo — capture from a real device running the release APK (record screen, live tracking, feed, a devotional). |

## 2. Data Safety form

Answers below are drawn directly from `docs/store_disclosures.md` — that
file has the full per-data-type table and reasoning; this is the condensed
version for filling in the console form.

- **Does your app collect or share user data?** Yes.
- **Is data encrypted in transit?** Yes (Supabase and Mapbox are both
  HTTPS-only).
- **Can users request data deletion?** Yes — in-app, Settings → Delete
  account.
- **Data types to declare:** Location (precise, and precise-background),
  Personal info (name), Photos (profile photo, optional), App activity
  (user-generated content: comments, scripture history, walk metadata).
- **Third-party sharing:** No app declares "shared with third parties" —
  Supabase, Mapbox and Google are service providers acting on the app's
  behalf, not recipients using the data for their own purposes. Re-confirm
  this framing against Play's current definition of "sharing" before
  submitting; it has changed before.
- **Data used for tracking across other apps/sites:** No, for every data
  type — there is no ad SDK and no analytics SDK anywhere in `pubspec.yaml`.

Walk through `docs/store_disclosures.md`'s full table row by row in the
console form — it already maps every collected field to Play's category
names as of when it was written.

## 3. Background location declaration

`ACCESS_BACKGROUND_LOCATION` is declared (see
`android/app/src/main/AndroidManifest.xml`) so this app goes through Play's
background-location access review — a manual review that has historically
taken days to several weeks. Do not schedule a launch date immediately
behind it.

- [ ] Fill in the declaration form using the justification copy already
      drafted in `docs/store_disclosures.md` under "Background location
      justification" — it explains what the feature does and why
      foreground-only location is not sufficient, in Play's expected shape.
- [ ] **Record the required demo video** on a real device, against the
      release build: start a recording, background the app or lock the
      screen, show the walk still tracking (e.g. reopen and see distance/time
      has advanced), then finish it. `docs/background_tracking.md` has the
      full walkthrough of the mechanism if the reviewer's questions need a
      more technical answer.
- [ ] If the review timeline becomes the binding constraint on a release
      date, `docs/background_tracking.md` documents the one-line fallback:
      removing the `ACCESS_BACKGROUND_LOCATION` line drops the app out of
      this review entirely, at the cost of losing GPS continuity across a
      process restart (the on-disk recording journal still recovers the walk
      itself either way).

## 4. Content rating questionnaire

Answer based on what's actually in the app:

- User-generated content: **yes** (comments, encouragements, profile bios,
  shared walks) — this pulls in Play's UGC disclosures and moderation
  requirements. `AdminModerationScreen` / the reports RPC exist for this.
- Shares user location with other users: **yes**, in the sense that a
  shared walk's route and place name are visible to followers by default —
  cross-check the current visibility model (`docs/` and the RLS policies)
  against how Play's questionnaire phrases this before answering.
- No violence, sexual content, gambling, or controlled-substance content
  categories apply.

## 5. Target audience & content

- Target age group: general audience, not primarily directed at children.
  Do not opt into the Families program unless that's a deliberate business
  decision — it carries additional policy requirements (ad content rules,
  data collection limits) that this app is not currently built to satisfy
  (it does collect precise location, tied to identity, which the Families
  policies restrict heavily).

## 6. App access — reviewer test credentials

**Reviewers cannot get past sign-in without credentials you provide.** The
app has two sign-in paths (`auth_screen.dart`): email/password and native
Google Sign-In. Recommended: create a dedicated review account with
**email/password**, not Google — it avoids Google's own reviewer needing a
working Google account against your OAuth consent screen, which is one
fewer moving part during review.

- [ ] Create a review-only member account (email + password) directly in the
      app or via Supabase, seeded with a walk or two so the feed and history
      aren't empty on first login.
- [ ] In Play Console → App content → App access, mark the app as requiring
      login and supply that email/password.
- [ ] If Google Sign-In should also be reviewable, note in the same field
      that it's an alternative path, not the only one — don't make it the
      reviewer's only option.

## 7. After the first upload — Play App Signing SHA-1

**This step is easy to forget and breaks Google Sign-In for every user who
installs from the Play Store, while continuing to work for you locally —
budget time to catch it before it reaches users.**

Play App Signing re-signs the uploaded AAB with Google's own key before
distributing it. The certificate that ends up on real installs is Play's,
not the upload keystore's, so Google Sign-In's Android OAuth client — which
is keyed to a specific SHA-1 — needs a second entry.

1. [ ] Play Console → your app → Release → Setup → App integrity → App
       signing key certificate → copy the **SHA-1** fingerprint.
2. [ ] Google Cloud Console → APIs & Services → Credentials → the Android
       OAuth client for `com.calledpresentations.prayer_walk` → add that
       SHA-1 alongside the existing upload-key one (keep both — the upload
       key's SHA-1 is what your own local installs and internal testing
       still use).
3. [ ] Install the app from Play (internal testing track is enough) and run
       Google Sign-In once to confirm it works end to end. If it fails here,
       `AuthDiagnosticsScreen` — reachable in a debug build — is built for
       exactly this: `aud` mismatch or a Credential Manager refusal both
       show up there without guessing. See `docs/google_sign_in_28444.md`
       for the known-error-code reference if the diagnostics point at
       `28444`.

## 8. Version

`pubspec.yaml` is currently `1.0.0+4`. Confirm the build number in
`pubspec.yaml` before every build — don't trust this doc, which drifts.

**The rule: increment the build number (the `+N` after the version name)
before every upload. Play permanently reserves every version code it has
ever seen, even for a release that was later discarded or never promoted
out of a track — there is no way to free up or reuse a number.** Codes 1,
2, and 3 were already consumed by earlier upload attempts (including one to
Production that was discarded); +4 is the next available number. The
version *name* (`1.0.0`) is what users see and does not need to change
between these attempts — only the build number does.
