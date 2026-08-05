/// Whether the isolated `GoogleSignIn.instance.authenticate()` probe issued a
/// token, was cancelled, refused outright, or hasn't run yet.
enum GoogleProbeOutcome { notRun, cancelled, refused, issued }

/// Whether the probe's token was, in turn, handed to Supabase and accepted.
enum SupabaseAcceptOutcome { notRun, accepted, rejected }

/// Turns the diagnostic screen's raw evidence into the one headline a
/// maintainer actually needs, instead of five rows they have to interpret
/// themselves.
///
/// Pulled out of `AuthDiagnosticsScreen` so it can be unit-tested without a
/// widget harness or a real Google/Supabase round trip.
abstract final class AuthDiagnosticsVerdict {
  /// The single plain-language conclusion for the state of a `Run all` pass.
  ///
  /// [refusalReason] is only read when [probe] is [GoogleProbeOutcome.refused]
  /// — see [classifyRefusal]. [audMatches] is only read when [probe] is
  /// [GoogleProbeOutcome.issued]: null means the token's `aud` claim couldn't
  /// be decoded at all, which is reported as its own row rather than guessed
  /// at here.
  static String headline({
    required GoogleProbeOutcome probe,
    String? refusalReason,
    bool? audMatches,
    SupabaseAcceptOutcome supabaseOutcome = SupabaseAcceptOutcome.notRun,
  }) {
    switch (probe) {
      case GoogleProbeOutcome.notRun:
        return 'Run all to see a verdict.';
      case GoogleProbeOutcome.cancelled:
        return 'You dismissed the Google sheet before it finished. Run all '
            'again and complete it.';
      case GoogleProbeOutcome.refused:
        return refusalReason ?? 'Google refused to issue a token.';
      case GoogleProbeOutcome.issued:
        if (audMatches == null) {
          return "Google issued a token, but its aud claim couldn't be read "
              '— see the Token audience row.';
        }
        if (!audMatches) {
          return 'Google issued a token for a different client ID than the '
              'app is configured with — GOOGLE_WEB_CLIENT_ID is wrong.';
        }
        return switch (supabaseOutcome) {
          SupabaseAcceptOutcome.notRun =>
            "Google issued a token with the right audience, but it wasn't "
                'handed to Supabase — see the Supabase row.',
          SupabaseAcceptOutcome.rejected =>
            'Google issued a token; Supabase rejected it. Add the Web '
                'client ID to Supabase → Auth → Providers → Google → '
                'Client IDs.',
          SupabaseAcceptOutcome.accepted => 'Everything passed.',
        };
    }
  }

  /// Names which of the dashboard-side faults a Google-side refusal points
  /// at, from the exception's `code.name` and description.
  ///
  /// Mirrors the classification `AuthRepository._mapUnknownError` applies to
  /// the same failure on the real sign-in path, deliberately duplicated
  /// rather than shared — this is diagnostic-only code, and reaching into the
  /// sign-in path to share a helper is exactly the kind of coupling that
  /// would make touching one risk breaking the other.
  static String classifyRefusal({required String code, String? description}) {
    final desc = (description ?? '').toLowerCase();
    switch (code) {
      case 'clientConfigurationError':
        return 'Google refused before showing anything: the native SDK '
            'rejected the client configuration. Check GOOGLE_WEB_CLIENT_ID '
            'is the Web client ID, not the Android one.';
      case 'providerConfigurationError':
      case 'uiUnavailable':
        return "Google sign-in isn't available on this device — it needs "
            'Google Play services.';
      case 'userMismatch':
        return "That Google account doesn't match the one already signed "
            'in on this device.';
      case 'interrupted':
        return 'Sign-in was interrupted before it finished. Run all again.';
      case 'unknownError':
        final looksLikeDevConsole =
            desc.contains('28444') || desc.contains('developer console');
        final looksLikeNoAccount =
            !looksLikeDevConsole &&
            (desc.contains('no accounts') ||
                desc.contains('no credentials available') ||
                desc.contains('add a google account'));
        if (looksLikeDevConsole) {
          return 'Google refused to issue a token. The account signing in '
              'is probably not a Test user on the OAuth consent screen — or '
              "the Android OAuth client is missing this build's package "
              'name / SHA-1.';
        }
        if (looksLikeNoAccount) {
          return "Google couldn't find an account on this device. Add a "
              'Google account, then run all again.';
        }
        return 'Google refused to issue a token and did not say why. On a '
            'rebuilt dev machine the likelier cause is the developer '
            'console (Test user, package name, SHA-1) rather than the '
            'device — but the evidence here cannot tell the two apart.';
      default:
        return 'Google refused to issue a token ($code). See the raw '
            'exception below.';
    }
  }
}
