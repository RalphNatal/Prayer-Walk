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
