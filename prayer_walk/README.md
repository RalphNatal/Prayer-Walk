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
