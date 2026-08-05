# Setting up on a new machine

What a fresh checkout on a fresh machine is missing, and why: everything below
is git-ignored on purpose (see `.gitignore`), so a clone is deliberately
incomplete until these are recreated.

---

## The short version

| Missing thing | Why it's git-ignored | Recreate it |
|---|---|---|
| `env.json` | Carries the Supabase URL/key and Google client IDs — hygiene, not secrecy (see `app_config.dart`'s own doc comment) | Copy `env.example.json` → `env.json`, fill in the values |
| Debug keystore | Auto-generated per machine by the Android SDK; not meant to be shared | Nothing to do — Gradle creates it on first build |
| Upload keystore (`*.jks`) | A real signing credential; losing it is a support ticket, leaking it is worse | Generate once with `keytool`, see `android/key.properties.example` |
| `android/key.properties` | Points at the upload keystore and carries its passwords | Copy `key.properties.example` → `key.properties`, fill in |

The part that actually breaks Google sign-in after a rebuild is the *debug*
keystore, because it's the one thing in this table with no configuration step
— it's just generated — and its SHA-1 fingerprint changes every time.

## Why a new machine breaks Google sign-in specifically

Android signs every build, debug included, with a keystore. The debug
keystore isn't checked in — Gradle generates `~/.android/debug.keystore`
automatically the first time you build, using whatever machine you're on. A
new SSD, a new user profile, a reinstalled Android SDK: any of these means a
**new debug keystore**, and a new debug keystore means a **new SHA-1
fingerprint**.

Google's Android OAuth client is registered against a specific SHA-1. Google's
own UI for an Android OAuth client holds **exactly one** SHA-1 — there's no
"add another" for the debug case. So a new machine doesn't just need its SHA-1
*added*; either the existing Android OAuth client's SHA-1 needs to be swapped
for the new one, or you need a second Android OAuth client for the new
machine.

Find the new SHA-1 with:

```
cd android
./gradlew signingReport
```

Look for the `SHA1` line under `Variant: debug`. Then, in Google Cloud
Console → APIs & Services → Credentials → the Android OAuth client for
`com.calledpresentations.prayer_walk`, either update its SHA-1 or add a second
Android client with the new one.

If sign-in still fails with error 28444 after the SHA-1 is registered
correctly, that's a different fault in the same error code — see
`docs/google_sign_in_28444.md`, and the debug-only diagnostic screen at
Settings → Diagnostics → Google sign-in config.

## Which client ID goes where

Three fingerprints end up mattering over the life of this app, and it's easy
to confuse them:

| Fingerprint | Where it comes from | Where it's registered |
|---|---|---|
| Debug SHA-1 | `gradlew signingReport`, regenerated per machine | Android OAuth client, for local `flutter run` builds |
| Upload-key SHA-1 | Your own `prayer-walk-upload.jks`, generated once | Android OAuth client, for your own installs from a release build |
| Play App Signing SHA-1 | Google's, generated on your **first** Play Console upload | Android OAuth client, for anyone installing from the Play Store |

The third one is easy to miss: Play App Signing re-signs your upload with
Google's own key before distributing it, so the certificate the outside world
actually sees is Google's, not the one from your `.jks`. Skip registering it
and Google Sign-In keeps working for your own installs — which use the upload
key's SHA-1 — while failing for everyone who installs from the Store. See the
"after first upload" section of `android/key.properties.example` for exactly
where to find it.

And separately from all three SHA-1s: the **Web** and **iOS** OAuth *client
IDs* (`GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` in `env.json`) aren't
tied to a machine or a keystore at all — they're per-Google-Cloud-project
values, the same on every machine, and Supabase's Authorized Client IDs must
list the Web one regardless of which machine or keystore is signing the app.
