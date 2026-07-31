/// The rules a profile field has to satisfy, in one place.
///
/// Both the form and the repository read these. The form so it can say what is
/// wrong before a round trip; the repository so that what reaches Postgres is
/// already inside the limits the columns declare, and a validator someone
/// forgets to wire up cannot turn into a 400 from the database.
///
/// Nothing here talks to Supabase or to Flutter — it is arithmetic on strings,
/// which is also what makes it the part of this feature a test can hold.
library;

/// Length caps. These mirror the `check` constraints in
/// `20260731010000_profile_public_fields.sql` and the existing `bio` limit the
/// form has always drawn; if one moves, the other has to move with it.
abstract final class ProfileLimits {
  static const displayName = 60;
  static const bio = 160;
  static const parish = 80;
  static const pronouns = 40;
  static const location = 80;
  static const links = 200;

  /// Handle length, counted without the leading `@`.
  static const handleMin = 3;
  static const handleMax = 24;
}

/// Letters, digits, underscore and a single interior dot or dash. No spaces, no
/// `@` beyond the stored prefix, nothing that changes meaning when a handle is
/// pasted into a URL or read aloud.
final _handleShape = RegExp(r'^[a-z0-9_]+([.\-][a-z0-9_]+)*$');

/// The stored form of what someone typed: lowercased, `@`-prefixed, trimmed.
///
/// Lowercased so `@Ana` and `@ana` cannot both exist and confuse people about
/// which one is which — the unique index is case-sensitive and would happily
/// keep them apart. Validation happens in [handleError]; this only canonicalises
/// what has already passed it.
String canonicalHandle(String value) {
  final bare = value.trim().replaceAll(RegExp(r'^@+'), '').trim();
  return '@${bare.toLowerCase()}';
}

/// What is wrong with [value] as a handle, or null if nothing is.
String? handleError(String value) {
  final bare = value.trim().replaceAll(RegExp(r'^@+'), '').trim();
  if (bare.isEmpty) return 'Pick a handle.';
  if (bare.length < ProfileLimits.handleMin) {
    return 'Handles are at least ${ProfileLimits.handleMin} characters.';
  }
  if (bare.length > ProfileLimits.handleMax) {
    return 'Handles are at most ${ProfileLimits.handleMax} characters.';
  }
  if (!_handleShape.hasMatch(bare.toLowerCase())) {
    return 'Letters, numbers, dots, dashes and underscores only.';
  }
  return null;
}

/// What is wrong with [value] as a display name, or null.
String? displayNameError(String value) {
  final name = value.trim();
  if (name.isEmpty) return 'Your profile needs a name.';
  if (name.length > ProfileLimits.displayName) {
    return 'That name is longer than ${ProfileLimits.displayName} characters.';
  }
  return null;
}

/// The one link a profile may carry, normalised — or null if [value] is not a
/// link this app will offer to open.
///
/// Only `https` and `http`. Not `javascript:`, not `data:`, not `file:`, and
/// not an app scheme that would hand a tap to whatever happens to be installed.
/// A bare `example.org` is read as `https://example.org`, because that is what
/// someone typing their parish's address means and refusing it teaches nothing.
///
/// Returns the normalised string so the caller stores what it validated rather
/// than storing the raw text and hoping the two agree.
String? profileLink(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  if (raw.length > ProfileLimits.links) return null;

  // A scheme-less string parses as a path, not a host, so give it one before
  // asking. `//` rather than a guessed scheme keeps an explicit `http://` intact.
  final candidate = raw.contains('://') ? raw : 'https://$raw';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  // `https://` alone parses cleanly and points nowhere. A host with a dot in it
  // is the cheapest check that rules out `https://localhost` typos too.
  if (!uri.host.contains('.')) return null;
  if (uri.toString().length > ProfileLimits.links) return null;
  return uri.toString();
}

/// What is wrong with [value] as a link, or null. Empty is fine — the field is
/// optional, and an optional field that scolds you for leaving it alone is a
/// bug.
String? linkError(String value) {
  if (value.trim().isEmpty) return null;
  return profileLink(value) == null
      ? 'That needs to be a web address, like prayerwalk.org.'
      : null;
}

/// Trims [value] and cuts it to [max]. The database has the same limit as a
/// `check` constraint, so this is about which one gets to be the error: a
/// pasted paragraph should land as a short field, not as a failed save.
String clampField(String value, int max) {
  final trimmed = value.trim();
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max).trim();
}
