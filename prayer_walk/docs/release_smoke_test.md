# Release-build smoke test

> Run this against the **release APK, on a physical device** — not the AAB
> (can't be sideloaded), not a debug build (R8 doesn't run, so it can't catch
> what only breaks under minification), and not an emulator for the
> background/lock-screen items. Install with:
>
> ```
> adb install build/app/outputs/flutter-apk/app-release.apk
> ```

R8 is enabled on release builds (`isMinifyEnabled = true` in
`android/app/build.gradle.kts`), and it can strip code that a debug build
never exercises this way — the Credential Manager keep rules in
`proguard-rules.pro` exist specifically because R8 once stripped Google
Sign-In's reflectively-loaded Play Services backend in release only. This
list exists to catch a regression there or anywhere else R8 or resource
shrinking could quietly break something debug builds can't reveal.

- [ ] **Google sign-in succeeds.** This is the highest-value check on this
      list — it's the one most likely to fail in release while working fine
      in debug. If it fails, `AuthDiagnosticsScreen` is not reachable from a
      release build by design (see the debug-surface verification below), so
      diagnosing it needs a debug build with the same `env.json` instead.
- [ ] **A walk records, saves, and survives an app restart.** Start a
      recording, walk (or simulate movement) for a minute or two, finish and
      save it, then force-stop and relaunch the app — confirm the saved walk
      is still there with its route intact.
- [ ] **Background recording continues with the screen locked.** Start a
      recording, lock the screen for a couple of minutes, unlock, and confirm
      distance/duration advanced during that span rather than freezing at the
      lock moment. Check the ongoing notification is visible while locked.
- [ ] **Scripture prompts arrive** during a walk — chime, spoken prompt (if
      enabled), and the marker appears on the route/summary afterward.
- [ ] **Account deletion completes.** Settings → Delete account, through to
      actual sign-out and the account no longer being able to sign back in.
      Use a throwaway test account for this, not a real one.
- [ ] **No diagnostic screen is reachable anywhere** — no Diagnostics entry
      under Settings, no "Run diagnostics" link on a failed sign-in, no
      `/auth-diagnostics` route reachable by any in-app action. (This is
      expected to hold automatically — see the debug-surface verification —
      but confirm it by trying the entry points that exist in debug: Settings
      list, and the sign-in failure dialog.)

If any of these fail in the release build but pass in debug, treat it as an
R8/shrinking issue first (check `android/app/proguard-rules.pro` for a
missing keep rule) rather than assuming the feature itself regressed.
