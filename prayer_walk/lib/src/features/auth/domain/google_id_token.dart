import 'dart:convert';

/// Reads claims out of a Google ID token's payload, for diagnostics only.
///
/// This deliberately does not verify the signature and never will — that
/// would need a JWT/crypto dependency this app doesn't otherwise carry, and
/// it isn't the point. Nothing here decides whether to trust a token; that is
/// Supabase's job, server-side, on the real sign-in path. All this answers is
/// "which client ID did Google mint this token for", so a maintainer can diff
/// it against `GOOGLE_WEB_CLIENT_ID` without guessing.
abstract final class GoogleIdToken {
  /// The token's `aud` claim, or null if [idToken] isn't shaped like a JWT or
  /// its payload doesn't decode to JSON with a string `aud`.
  static String? decodeAudClaim(String idToken) {
    final segments = idToken.split('.');
    if (segments.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(segments[1])),
      );
      final json = jsonDecode(payload);
      if (json is Map && json['aud'] is String) return json['aud'] as String;
      return null;
    } catch (_) {
      // Malformed base64, malformed JSON, or a payload shaped unlike a token
      // — all the same answer here: this doesn't tell us anything.
      return null;
    }
  }
}
