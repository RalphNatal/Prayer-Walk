# Recording that survives a pocket

Everything about a walk continuing once the phone leaves the walker's hand: what
was built, which permissions it asks for and when, what the walker is told, what
has to be verified on a real device, and what the two stores will want at
submission.

---

## The choice, and why

Two credible ways to keep a recording alive in the background:

| | `flutter_background_geolocation` | **A foreground service + geolocator (chosen)** |
|---|---|---|
| Licence | Commercial, per-app | None |
| Doze / App Standby | Handled | Handled by the FGS + a wake lock |
| OEM battery managers | Actively worked around | Not worked around; explained to the walker |
| Motion-triggered wake | Yes | No — the walk is continuous anyway |
| Crash / process-death recovery | Built in, native side | Ours: a journal on disk, offered back on relaunch |
| Plugin surface | A second location plugin alongside geolocator | One plugin, still sealed in `location_service.dart` |

**Chosen: option 2.** geolocator is already in the project and already sealed
behind one file, and the parts of option 1 that are genuinely hard to reproduce
— motion-triggered wake, native crash recovery — are the parts this app needs
least. A prayer walk is a continuous half-hour, not a day of intermittent
tracking; and process death is recovered here in Dart, where it can be *offered*
to the walker rather than silently resumed.

**What that costs us, stated plainly.** Aggressive OEM battery managers —
Xiaomi, Huawei, Samsung, Oppo, OnePlus — can and will kill a long-running
foreground service on some devices whatever it asks for. `flutter_background_geolocation`
carries per-vendor workarounds for this and we do not. Our answer is the journal
(nothing is lost when it happens) plus a contextual explanation offered only to
the walkers it actually happened to. If field reports show it happening often on
a specific handset, revisiting option 1 is the honest next step.

---

## How it works

### Android

The mechanism is a **foreground service typed `location`**. A service of that
type, started while the app is on screen, may read location for as long as it
runs on nothing more than `ACCESS_FINE_LOCATION`. `ACCESS_BACKGROUND_LOCATION`
is *not* what makes a backgrounded walk work.

geolocator starts that service when — and only when — the position stream is
opened with a `foregroundNotificationConfig`. `LocationService.positionStream`
attaches one if, and only if, `background: true`, and the recorder passes true
for a recording and never anywhere else. Cancelling the subscription tears the
service, its notification and its wake lock down.

### iOS

`allowBackgroundLocationUpdates` plus `UIBackgroundModes: location`. When-in-use
is sufficient; the app never calls `requestAlwaysAuthorization` for its own
sake. `pauseLocationUpdatesAutomatically` is **false** — iOS pausing updates
mid-walk is a common cause of a truncated track, and of a walk that never
un-pauses. `showBackgroundLocationIndicator` is true for the same span, so the
blue pill is on screen for exactly as long as the app is reading location.

Both one-shot settings set these explicitly to `false`, because `AppleSettings`
defaults `allowBackgroundLocationUpdates` to **true** — the record screen
centring its map must not put the blue indicator up.

---

## Permissions

### Android manifest

| Permission | Why |
|---|---|
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | The walk itself. Asked for first, at the first Start. |
| `ACCESS_BACKGROUND_LOCATION` | Resilience only — lets the service keep reading if the process is restarted by the system. Asked for separately, later. **This is the line that triggers Play's background-location review.** |
| `FOREGROUND_SERVICE` | Required to run any foreground service. |
| `FOREGROUND_SERVICE_LOCATION` | Required from Android 14 for the `location` service type. |
| `POST_NOTIFICATIONS` | Android 13+ will not *display* the ongoing notification without it. The service runs either way. |
| `WAKE_LOCK` | The `PARTIAL_WAKE_LOCK` geolocator holds while `enableWakeLock` is set. Without it Doze batches fixes and delivers them in a clump. |
| `ACTIVITY_RECOGNITION` | Unchanged — step-paced scripture only, and only if chosen. |

The service is also declared explicitly in the app manifest, with attributes
byte-identical to geolocator's own. It merges to the same result; declaring it
here means the one thing a store reviewer needs to see is in this app's manifest
rather than a dependency's. **If a geolocator upgrade breaks the manifest
merger, that duplicate declaration is why.**

### iOS Info.plist

| Key | Value |
|---|---|
| `UIBackgroundModes` | `["location"]` |
| `NSLocationWhenInUseUsageDescription` | Names route tracing, and says location is read only between Start and Finish. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Required alongside the background mode. Names the pocket and the locked screen. |
| `NSLocationTemporaryUsageDescriptionDictionary` | Unchanged — the precise-accuracy upgrade. |
| `NSMotionUsageDescription` | Unchanged — step cadence. |

Purpose strings are specific on purpose. Vague ones ("to improve your
experience") are among the most common reasons a location app fails App Review.

### The order the walker sees, and why it is that order

Everything is asked at the **first press of Start** and never at launch:

1. **Location, when-in-use.** Blocking: no grant, no walk. Existing behaviour.
2. **Notifications** (Android 13+). Not blocking. Refusing hides the ongoing
   notification; the walk still records.
3. **Background location** (Android 10+). Not blocking, asked at most once per
   install, and only after (1) has been granted.

Step 3 has to be separate. Android 11 and above answer a request that mixes
foreground and background location by showing **nothing** and granting nothing —
so a bundled request would be a Start button that silently does nothing.

That is also why `permission_handler` now appears inside
`location_service.dart`. `Geolocator.requestPermission()` on Android appends
`ACCESS_BACKGROUND_LOCATION` to the same `requestPermissions` call whenever the
manifest declares it (see `PermissionManager.requestPermission` in
`geolocator_android`), which is exactly the broken shape. permission_handler
asks for fine/coarse alone, and for background alone. **geolocator remains the
only thing that reads a position**; permission_handler only asks questions, and
both stay behind the same one file.

On Android 11+, `Permission.locationAlways.request()` returns
`permanentlyDenied` almost immediately — the platform stopped showing a dialog
for background location and moved it to a settings page. That is the expected
answer, not a failure, and nothing in the app treats it as one.

---

## What the walker is told

Copy currently in the app, all of it load-bearing:

**Record screen, under Start**
> Your route keeps recording with the screen locked or the phone in a pocket. A
> notification shows while a walk is running, and your location is read only
> between Start and Finish.

**Live screen, under the controls**
> Recording continues with your phone in a pocket or the screen locked. It stops
> when you tap Finish.

**Android ongoing notification** — title `Prayer Walk`, body
`Recording your walk. Tap to open it.`, channel `Walk recording`, ongoing
(not swipeable), tapping it returns to the walk.

*The notification text cannot show live distance or elapsed time.* geolocator
takes the notification configuration once, when the stream is listened to, and
exposes no way to rewrite it. The only route to a changing number would be to
tear down and re-open the stream every few seconds, which would cost the GNSS
lock each time. It says the true unchanging thing instead of a stale number.

**Interrupted-walk card** (record screen; appears only after an interruption)
> **You have an unfinished walk**
> 2.4 km · 31:07 · stopped 12 minutes ago. Carry on with it, or save it as it is.
>
> [Pick it up] [Save it] — Why did this happen? · Throw it away

**"Why did this happen?"**
> Prayer Walk keeps recording in the background, but some phones — Xiaomi,
> Huawei, Samsung, Oppo and OnePlus especially — close apps that run for a long
> time with the screen off, whatever the app asks for.
>
> If this keeps happening, find Prayer Walk in your phone's Settings, open
> Battery, and set it to Unrestricted (some phones call it "Don't optimise" or
> "Allow background activity").

### On not nagging about battery optimisation

There is no reliable detection here, and we deliberately did not fake one.
`Permission.ignoreBatteryOptimizations.status` reports `denied` whenever
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is absent from the manifest — so
"detecting" it would mean declaring a permission Google Play restricts to a
narrow list of app types, and then warning every walker on every phone whether
or not they have a problem.

Instead the app uses the one piece of *evidence* it genuinely has: **a walk was
actually interrupted.** The explanation is attached to that walk's recovery
card, behind a link the walker chooses to tap. Walkers whose phones behave never
see it.

---

## Surviving process death

`RecordingJournal` writes the walk in progress to `SharedPreferences`
(`recording.inProgress.v1`) as it accumulates:

- **Throttled to once every 4 seconds** for ordinary progress — roughly every
  other fix at the 5 m filter. The snapshot is held unencoded until it is
  actually written, so a coalesced write costs nothing.
- **Immediately, off the throttle**, for anything that would be felt if it were
  lost: a waypoint marked, a verse delivered, a pause or resume, a mute, the end
  of a walk, and the app being backgrounded (`onHide` / `onPause` / `onDetach`).

What is stored: activity type, start time, last-written time, moving time,
distance, elevation gain, the whole route, waypoints, intentions, delivered
prompts (the full prompt, not just its id), this walk's scripture settings, the
devotional it was started from, and whether it was paused. Route, waypoints and
intentions use the same JSON shape as the `activities` row, via
`activity_row_mapper.dart`, so there is one definition of what a waypoint is.

Worst case for a 10 km walk: roughly 2,000 points, ~60 KB of JSON, rewritten
every 4 s.

**On relaunch** `interruptedRecordingProvider` reads it once and the record
screen offers three doors — *Pick it up*, *Save it*, *Throw it away* (which
asks first). Nothing resumes by itself: silently restarting the GPS and the
notification for somebody who finished walking an hour ago and opened the app to
read the feed would be its own failure. Pressing Start with an unresolved walk
waiting asks before overwriting it.

Two deliberate rules:

- **Moving time is not topped up** with the wall-clock time the app was dead.
  Nobody knows whether those minutes were walked. Same rule a pause follows.
- **Resuming starts a new segment** (`_previous` is null, the warm-up gate
  re-arms), so the gap between where the walk died and where it is picked up is
  never drawn or measured as a leg.

Walks lost more than 6 hours ago are still offered, but only as something to
save — resuming would stitch two different walks together.

---

## What did not change, and was checked

- The noise filters: >25 m rejected, <3 m ignored, climb above 1.5 m. Untouched.
- The warm-up gate: 20 s or `≤20 m` accuracy, whichever comes first. Untouched,
  and re-armed on a resume.
- Pause/resume with no phantom leg. Untouched.
- Sampling: `distanceFilter: 5`, `intervalDuration: 1 s`,
  `bestForNavigation`. Deliberately unchanged — sampling harder to compensate
  for background behaviour would buy nothing but battery.

## What did change beyond the background plumbing

Three things had to move for the acceptance criteria to be reachable. All three
are behaviour changes worth a maintainer's attention:

1. **Scripture is announced by the recorder, not the live screen.** The chime,
   the voice and the screen-reader announcement used to hang off a `ref.listen`
   in `LiveTrackingScreen`, so a verse arriving with the app on another tab or
   behind a lock screen dropped its marker in silence. `RecordingController`
   outlives every screen, so announcing from there is the only place it can be
   right.

2. **iOS audio no longer respects the Silent switch during a walk.** The
   announcer used the `ambient` category, chosen so a silenced phone stayed
   silent. `ambient` also does not play in the background — the same property of
   the same category — so respecting the switch meant the voice worked only when
   it was not needed. It is now `playback` with `duckOthers`. **This reverses a
   documented product decision and is the one thing here most worth a second
   opinion.** The mute button on the live screen and the two settings toggles
   are the controls now; both channels are off unless the walker turned them on.
   (The old configuration also tripped `AudioContextConfig`'s own iOS assertion:
   `respectSilence` and `duckOthers` cannot both be set, so the chime was
   throwing in debug on iOS.)

3. **Elapsed time is read off the wall clock**, not counted in ticks. A
   `Timer.periodic` that misses a beat because the OS deferred it used to be a
   second of somebody's walk quietly gone; backgrounded, that is not rare.

One deliberate departure from the brief: **a paused walk keeps its subscription
and therefore its foreground service.** Dropping them would cost the GNSS lock
on every prayer stop, and Android 12+ forbids *starting* a foreground service
from the background — so a walker who paused with the phone in a pocket could
never resume. A pause is inside a recording, not outside one, and the
notification on screen says so.

---

## Battery

**Not measured.** This required a physical device and a 30-minute background
walk, neither of which was available. Publishing a number nobody took would be
worse than the gap.

What can be said: the sampling is unchanged from the foreground-only build
(`bestForNavigation`, 5 m, 1 s), so the marginal cost of this work is the
foreground service, the `PARTIAL_WAKE_LOCK` preventing Doze, and the screen
being off rather than on — which usually makes the total *lower* than a
foreground walk with the display lit. The dominant cost in both cases is
continuous GNSS. For a `bestForNavigation` fix rate, 5–12 % per hour is the
usual range for this class of app; treat that as an expectation to check, not a
measurement.

**How to measure it, on device:**

```bash
# Android — a clean 30-minute background walk
adb shell dumpsys batterystats --reset
# ...record a walk for 30 minutes with the screen off...
adb shell dumpsys batterystats --charged com.calledpresentations.prayer_walk > stats.txt
# Then: https://developer.android.com/topic/performance/power/battery-historian
```

iOS: Xcode → Debug Navigator → Energy Impact during a wired session, or
Settings → Battery → Prayer Walk → "Activity" after an untethered walk.

---

## Still to verify on a device — an emulator cannot do any of this

- [ ] 30+ minutes recording with the app backgrounded, another app in front, and
      the screen locked. Distance/pace/elevation within GPS noise of a
      foregrounded walk; no truncation, no phantom legs.
- [ ] Navigating to another tab mid-walk never interrupts recording.
- [ ] Android: the ongoing notification appears for the whole recording,
      disappears when it ends, and tapping it returns to the live screen.
      **Highest-risk item:** geolocator creates its channel at
      `IMPORTANCE_NONE`, which on some OEM builds minimises the notification;
      and it is hidden entirely if `POST_NOTIFICATIONS` was refused.
- [ ] Android: the notification icon renders as a white silhouette, not a grey
      blob (`drawable/ic_stat_recording.xml`, a framework vector — verify on
      API 23/24 as well as current).
- [ ] iOS: the blue background-location indicator appears during a recording and
      **only** during one — including that centring the record screen's map does
      not show it.
- [ ] Killing the app mid-recording (swipe from recents, or
      `adb shell am kill`) and relaunching offers resume/save with nothing lost.
- [ ] Scripture arriving while backgrounded still chimes, speaks and drops its
      marker — on iOS with the screen locked, and with music playing.
- [ ] Background location prompt appears once, at the first Start, after the
      when-in-use grant — never at launch, never bundled.
- [ ] Battery over a 30-minute background walk, both platforms.
- [ ] Release builds: `flutter build appbundle` and `flutter build ipa`.

---

## Store submission — this affects release timelines

### Google Play

`ACCESS_BACKGROUND_LOCATION` puts this app into Play's **background location
access declaration and review**. It is not a checkbox:

- A declaration form in Play Console: the feature, why foreground-only will not
  do, and a **video** showing the in-app disclosure and the runtime permission
  flow.
- A **prominent in-app disclosure** shown before the permission request. The
  record-screen line under Start is written to be that disclosure; verify the
  final wording against the current policy before submitting.
- Review turnaround has historically run **days to several weeks**, and a
  rejection means another round. Budget for it; do not schedule a launch behind
  an unreviewed background-location declaration.

**The supported way out:** the foreground service — not
`ACCESS_BACKGROUND_LOCATION` — is what satisfies every acceptance criterion
here. Removing that one `<uses-permission>` line from the manifest drops the app
out of the declaration process entirely, at the cost of the process-restart case
(which the journal already covers by offering the walk back). If the review
timeline is the binding constraint on a release, that is the lever, and it is a
one-line change.

Also note: `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE_LOCATION` and `WAKE_LOCK`
need no declaration. The foreground service type must match the manifest, which
it does.

### App Store

- Background modes are reviewed against the app's actual behaviour. Recording a
  route is a well-understood justification; the purpose strings above name it
  directly.
- App Review Guideline 2.5.4 — an app may not use background location without a
  clear, visible benefit to the user. The blue indicator during a recording and
  the copy on both screens are that.
- Expect a reviewer to check that location stops when the walk does. It does:
  the flag is set for exactly the span of the subscription.

### Privacy labels — both stores

Precise location, collected, **linked to the user**, used for App Functionality.
Routes are stored on `activities` and are followers-only by default. Location is
read only between Start and Finish, which both purpose strings say and which the
code enforces in one place.
