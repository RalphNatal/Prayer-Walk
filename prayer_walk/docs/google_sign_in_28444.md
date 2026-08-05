# Diagnosing Google sign-in error 28444

What `[28444] Developer console is not set up correctly.` actually means, why
it can't be fixed from inside the app, and how to find the real cause when the
Dart-side error is this vague.

---

## Why this error is unhelpful on its own

Android's Credential Manager reports Google sign-in failures through
`GoogleSignInException`, whose `unknownError` code is a catch-all: "Credential
Manager had nothing to hand back." The `[28444]` description that comes with
it — "Developer console is not set up correctly" — is Google's own text, not
this app's, and it collapses **four unrelated dashboard-side faults** into one
string:

1. **`GOOGLE_WEB_CLIENT_ID` in `env.json` is not actually the Web client ID.**
   The Android and Web OAuth clients for the same project have IDs that look
   nearly identical — same suffix, similar length — and it is easy to paste
   the wrong one.
2. **The OAuth consent screen is in Testing, and the signing-in account isn't
   added as a Test user.** A Testing consent screen rejects any Google
   account not explicitly listed.
3. **Supabase's Google provider doesn't trust the token.** Supabase → Auth →
   Providers → Google → **Authorized Client IDs** must contain the Web client
   ID, or Supabase rejects an otherwise-valid Google ID token.
4. **The package name + SHA-1 aren't registered on an Android OAuth client.**
   Each Android OAuth client in Google Cloud Console is scoped to one
   `applicationId` and one signing certificate.

A fifth, quieter possibility: the Web and iOS client IDs were issued under
**two different Google Cloud projects**. Nothing about that shows up unless
the two IDs are compared side by side.

None of these five can be fixed from inside the app — they're all dashboard
configuration in Google Cloud Console or Supabase. What the app *can* do is
narrow down which one it is, rather than leave a guess.

## Where to look first: the in-app diagnostic

Debug builds have a Google sign-in diagnostic screen (`auth_diagnostics_screen.dart`)
that is reachable **without signing in** — the whole point, since sign-in being
broken is exactly when you need it:

* a "Diagnostics" link on the sign-in screen itself, below the form;
* a "Run diagnostics" action on the sign-in failure dialog, next to "Copy details";
* **Settings → Diagnostics → Google sign-in config**, for a maintainer who is
  already signed in on another account.

**Run all** checks each of the above mechanically — presence and shape of
every config value, whether the Web and iOS client IDs share a Google Cloud
project number, Supabase reachability, and the runtime package name — and
then goes further: it attempts a real `GoogleSignIn.instance.authenticate()`
in isolation and reports exactly what comes back, decodes the resulting ID
token's `aud` claim to catch a wrong `GOOGLE_WEB_CLIENT_ID` directly, and, if
that matches, carries the token all the way to a real Supabase exchange. That
last step is a genuine sign-in attempt — if it succeeds, the session is real —
because it's the only way to tell "Google refused" apart from "Google issued a
token and Supabase rejected it" with evidence instead of a guess. All of that
lands in one plain-language verdict, not a checklist to interpret. Its
**Copy report** button produces a pasteable block — including the verdict, the
full Web client ID, and the observed `aud` — with the Supabase key redacted
and no tokens. Start there before going to `adb logcat`.

## Native log capture

The Dart layer only ever sees the sanitised `GoogleSignInException` — the
real Android-side error, including which of the checks above actually failed,
is in `adb logcat` and never reaches Dart. Capture it while reproducing the
failure:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -c
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat | Select-String -Pattern "CredMan|Credential|GoogleSign|28444"
```

The first command clears the buffer so old noise doesn't drown out the
failure; the second streams matching lines while you tap "Continue with
Google" on the device.

**`GetCredentialResponse error returned from framework`** is the signature of
a Credential Manager rejection specifically — the line immediately after it
names the actual cause (a specific consent-screen or client-ID complaint from
Google Play Services), which `[28444]` alone does not.

## The four things to check, in order

This is also what the app's own error message says in debug builds when
`unknownError` fires and the description doesn't clearly point at a missing
device account:

1. `GOOGLE_WEB_CLIENT_ID` is the **Web** client ID, not the Android one.
2. The signing-in Google account is a **Test user**, if the consent screen is
   in **Testing**.
3. Supabase → Auth → Providers → Google → **Authorized Client IDs** contains
   that Web client ID.
4. The package name and SHA-1 are registered on an **Android** OAuth client.

If all four check out and it's still failing, compare the Web and iOS client
IDs' project-number prefixes (the digits before the first `-`) in the
diagnostic screen — a mismatch means the credentials live in different
Google Cloud projects.
