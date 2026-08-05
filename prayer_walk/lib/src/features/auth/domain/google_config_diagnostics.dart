/// Shape checks for Google OAuth client IDs, pulled out of the diagnostic
/// screen so they can be unit-tested without a widget harness.
///
/// None of this proves a client ID is *correct* — only Google Cloud Console
/// knows that. It catches the two things a plain string comparison can catch:
/// the ID isn't shaped like a client ID at all, or two IDs that should share a
/// Google Cloud project don't.
abstract final class GoogleConfigDiagnostics {
  static const _suffix = '.apps.googleusercontent.com';

  /// Whether [clientId] ends in the expected suffix and has a numeric
  /// project-number prefix ahead of the first `-`. Not proof it is registered
  /// anywhere — only that it isn't obviously the wrong kind of string (an API
  /// key, a bundle ID, empty).
  static bool hasPlausibleShape(String clientId) {
    if (clientId.isEmpty || !clientId.endsWith(_suffix)) return false;
    final prefix = projectNumberPrefix(clientId);
    return prefix != null && int.tryParse(prefix) != null;
  }

  /// The leading digits before the first `-`, e.g. `123456789012` out of
  /// `123456789012-abc123.apps.googleusercontent.com`.
  ///
  /// Every OAuth client issued under the same Google Cloud project shares this
  /// prefix. Two client IDs in this app — the Web one and the iOS one — are
  /// expected to share it; when they don't, the credentials were issued under
  /// two different projects, which is otherwise invisible from either ID read
  /// on its own.
  static String? projectNumberPrefix(String clientId) {
    final dash = clientId.indexOf('-');
    if (dash <= 0) return null;
    return clientId.substring(0, dash);
  }
}
