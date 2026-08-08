import 'package:flutter/foundation.dart' show kDebugMode;

/// Runtime configuration, read from `--dart-define`s at build time.
///
/// Every value comes from the environment via [String.fromEnvironment], which
/// means it is baked in at compile time from `env.json`:
///
/// ```
/// flutter run --dart-define-from-file=env.json
/// ```
///
/// Nothing here is a secret in the app-security sense — the Supabase
/// publishable/anon key and the Google client IDs are all safe to ship in a
/// client. They are read from a git-ignored `env.json` for hygiene and so they
/// can be rotated without touching source. The Supabase service_role key and
/// the Google *web client secret* are never referenced by the app at all.
abstract final class AppConfig {
  /// `https://<ref>.supabase.co`
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's publishable (or anon) key from Settings → API.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// The **Web** OAuth client ID. Passed as `serverClientId` on Android.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// The **iOS** OAuth client ID. Passed as `clientId` on iOS.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Mapbox public access token (`pk.…`), for basemap tiles and geocoding.
  ///
  /// Deliberately **not** in [validate]'s required list. A missing token
  /// degrades the map to the public OSM tiles rather than failing the launch —
  /// see [RouteMapView] — because an unconfigured dev build should still run.
  /// A production build must set it: the public OSM tile server is
  /// community-funded and its usage policy does not permit app traffic.
  static const mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static bool get hasMapboxToken => mapboxAccessToken.isNotEmpty;

  /// Which translation this build delivers on a walk — `WEBBE` or `NLT`.
  ///
  /// The whole app switches editions from here, without a content rewrite: both
  /// sets can sit in `scripture_prompts` at once, each row carrying its own
  /// `translation`, and this decides which of them a walk draws from. Prayers
  /// are delivered whatever it says — they quote nobody.
  ///
  /// Deliberately **not** in [validate]'s required list, and deliberately
  /// defaulted rather than empty: an unset value must mean the public-domain
  /// set, never "no scripture" and never a licensed edition by accident. The
  /// bundled offline set stays WEBBE regardless of this — see
  /// `ScripturePromptStore`.
  static const scriptureTranslation = String.fromEnvironment(
    'SCRIPTURE_TRANSLATION',
    defaultValue: 'WEBBE',
  );

  /// How many days a passage rests before it may be delivered again.
  ///
  /// The cooldown in "unseen first, then least recently seen": a prompt this
  /// member received inside this window is skipped entirely while anything
  /// else remains, so a verse from yesterday does not come back today. It is a
  /// preference, not a bar — a walk long enough to exhaust everything else
  /// falls back to oldest-first rather than going quiet.
  ///
  /// Configurable so a parish with a small library can shorten it rather than
  /// spend the whole pool at once, and so a very large library can lengthen it.
  /// Thirty days is the default because it is longer than the interval at which
  /// anybody remembers a short passage, and short enough that a 300-prompt
  /// library is not effectively halved by it.
  static const scriptureCooldownDays = int.fromEnvironment(
    'SCRIPTURE_COOLDOWN_DAYS',
    defaultValue: 30,
  );

  /// An internal marker appended to the version shown in Settings — e.g.
  /// `internal` or `qa` — for a build handed out ahead of a store release.
  /// Empty by default, so a store build shows a plain version number with
  /// nothing hardcoded to say otherwise.
  ///
  /// Set with `--dart-define=PW_BUILD_LABEL=internal`.
  static const buildLabel = String.fromEnvironment('PW_BUILD_LABEL');

  /// Whether the Google sign-in diagnostics screen is reachable.
  ///
  /// Always on in debug. In release it is off unless explicitly requested with
  /// `--dart-define=PW_ENABLE_DIAGNOSTICS=true`, so an internal testing build
  /// can carry the diagnostic that a store build must not ship.
  ///
  /// This exists because the sign-in failure being chased only happens in a
  /// Play-distributed release build — which, gated on `kDebugMode`, was
  /// precisely the build with no diagnostic in it. Off by default, so nothing
  /// changes for a store build unless someone asks for it on the command line.
  static const diagnosticsEnabled =
      kDebugMode || bool.fromEnvironment('PW_ENABLE_DIAGNOSTICS');

  /// Throws a [StateError] naming **every** missing key at once if any required
  /// compile-time value is absent.
  ///
  /// Call this before anything that reads the config (e.g. [Supabase.initialize]
  /// or Google sign-in) so an unconfigured launch fails with a readable message
  /// instead of an opaque network error later — or a blank white screen.
  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
      if (googleWebClientId.isEmpty) 'GOOGLE_WEB_CLIENT_ID',
      if (googleIosClientId.isEmpty) 'GOOGLE_IOS_CLIENT_ID',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing compile-time config: ${missing.join(', ')}.\n'
        'Run with: flutter run --dart-define-from-file=env.json',
      );
    }
  }
}
