import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        AuthRetryableFetchException,
        PostgrestException,
        StorageException;

import '../diagnostics/schema_manifest.dart';
import '../widgets/error_report_dialog.dart';
import 'app_exception.dart';

/// One failure, described three ways.
///
/// The point of this class is that a screen never has to guess. It shows
/// [message] to the person, writes [diagnostic] to the log, and — if they ask
/// for it — puts [code] and [details] on screen through [toReport].
///
/// Nothing here speculates about a cause. Every line of copy below is reached
/// from a code the server actually sent; anything unrecognised gets the neutral
/// fallback the caller supplied and keeps its raw text in [details], where it
/// can be read rather than guessed at.
@immutable
class AppErrorInfo {
  const AppErrorInfo({
    required this.message,
    required this.code,
    required this.diagnostic,
    this.details,
    this.isTransport = false,
    this.isMapped = false,
    this.isSchemaMissing = false,
  });

  /// One line for the person holding the phone.
  final String message;

  /// The machine-readable key: `postgres:42703`, `auth:invalid_grant`,
  /// `transport:ClientException`, `unhandled:FormatException`.
  final String code;

  /// A single greppable line for the log — type, message, code, hint.
  final String diagnostic;

  /// Raw exception text, for the details dialog and the clipboard.
  final String? details;

  /// True only for a genuine transport failure. This is the *only* case that
  /// may tell someone to check their connection.
  final bool isTransport;

  /// Whether the cause was recognised. False means [message] is the caller's
  /// neutral fallback and the details affordance is doing the real work.
  final bool isMapped;

  /// The database does not have something the app asked for by name — a table,
  /// a column or an RPC that a migration in `supabase/migrations/` creates and
  /// nobody has run yet.
  ///
  /// Distinct from a failure on purpose. Nothing the person does will fix it,
  /// so a screen showing this must not offer a retry as if it might, and it is
  /// emphatically not an empty list: the shelf isn't bare, the shelf isn't
  /// there. `ErrorStateView` reads this to pick between the three.
  final bool isSchemaMissing;

  ErrorReport toReport({
    required String tag,
    String title = ErrorReport.defaultTitle,
    StackTrace? stackTrace,
  }) => ErrorReport(
        tag: tag,
        title: title,
        code: code,
        message: message,
        details: details,
        // A stack is developer-facing noise on a shipped build; in debug it is
        // most of the value.
        stackTrace: kDebugMode ? stackTrace : null,
      );
}

/// Turns [error] into copy, a code and a diagnostic.
///
/// [fallback] is what the person reads when the cause is not one this knows —
/// it should name the action that failed ("The walk didn't save.") and nothing
/// else. Do not phrase it as a connection problem: that claim is added here,
/// and only when the error really is one.
///
/// [uniqueMessage] is the caller's copy for a unique-constraint clash, which is
/// only meaningful in context — a taken handle on the profile form, a duplicate
/// slug elsewhere.
AppErrorInfo describeFailure(
  Object error, {
  required String fallback,
  String? uniqueMessage,
}) {
  if (error is PostgrestException) {
    return _postgrest(error, fallback, uniqueMessage);
  }
  // Ahead of [AuthException]: Supabase's retryable fetch failure is a subclass
  // of it, and it is the network rather than anything about the credentials.
  if (_isTransport(error)) {
    return AppErrorInfo(
      message: '$fallback Check your connection, then try again.',
      code: 'transport:${error.runtimeType}',
      diagnostic: 'transport ${error.runtimeType}: $error',
      details: '$error',
      isTransport: true,
      isMapped: true,
    );
  }
  if (error is AuthException) {
    return AppErrorInfo(
      message: error.message,
      code: 'auth:${error.code ?? error.statusCode ?? 'unknown'}',
      diagnostic:
          'AuthException code=${error.code ?? 'none'} '
          'status=${error.statusCode ?? 'none'}: ${error.message}',
      details: '$error',
      isMapped: true,
    );
  }
  if (error is StorageException) {
    return AppErrorInfo(
      message: fallback,
      code: 'storage:${error.statusCode ?? 'unknown'}',
      diagnostic:
          'StorageException status=${error.statusCode ?? 'none'}: '
          '${error.message}',
      details: '$error',
    );
  }
  // Already written for the person by whoever threw it.
  if (error is AppException) {
    return AppErrorInfo(
      message: error.message,
      code: 'app:handled',
      diagnostic: 'AppException: ${error.message}',
      details: '$error',
      isMapped: true,
    );
  }
  return AppErrorInfo(
    message: fallback,
    code: 'unhandled:${error.runtimeType}',
    diagnostic: 'unhandled ${error.runtimeType}: $error',
    details: '$error',
  );
}

AppErrorInfo _postgrest(
  PostgrestException error,
  String fallback,
  String? uniqueMessage,
) {
  final code = error.code ?? 'none';
  final diagnostic =
      'PostgrestException code=$code: ${error.message}'
      '${error.details == null ? '' : ' | details: ${error.details}'}'
      '${error.hint == null ? '' : ' | hint: ${error.hint}'}';
  final details = [
    'code: $code',
    'message: ${error.message}',
    if (error.details != null) 'details: ${error.details}',
    if (error.hint != null) 'hint: ${error.hint}',
  ].join('\n');

  // The database does not have something this app asked for by name. Handled
  // ahead of the table below because all four codes share one diagnosis, one
  // fix, and one extra paragraph of details — see [_missingSchema].
  final missing = _kMissingSchemaCodes[code];
  if (missing != null) {
    return _missingSchema(
      error,
      code: code,
      kind: missing,
      diagnostic: diagnostic,
      details: details,
    );
  }

  // The message is the caller's fallback unless the code says something
  // definite. Every branch below is a code Postgres or PostgREST sent.
  final (String message, bool mapped) = switch (code) {
    '42501' => ("You don't have permission to do that.", true),
    '23505' => (uniqueMessage ?? 'That already exists.', true),
    '23503' => ('That item no longer exists.', true),
    '23514' => ("That value isn't allowed.", true),
    'PGRST116' => ("We couldn't find that.", true),
    'PGRST301' => ('Your session has expired. Sign in again.', true),
    _ => (fallback, false),
  };

  return AppErrorInfo(
    message: message,
    code: 'postgres:$code',
    diagnostic: diagnostic,
    details: details,
    isMapped: mapped,
  );
}

/// What kind of database object the server could not find.
enum _MissingKind {
  table('table', "This part of the app isn't set up on the server yet."),
  column('column', 'The app is newer than the server.'),
  function('function', "This part of the app isn't set up on the server yet.");

  const _MissingKind(this.label, this.debugMessage);

  /// The word for the thing, for the log line and the details block.
  final String label;

  /// What a developer reads. In release nobody sees this — see
  /// [_releaseMissingMessage].
  final String debugMessage;
}

/// The four codes that all mean "a migration has not been applied".
///
/// Two are PostgREST's — it keeps its own cache of the schema and answers from
/// that — and two are raw Postgres, which is what comes back for an RPC that
/// resolved but then touched something absent. Same cause, same fix, so they
/// share a branch rather than drifting apart in four places.
const Map<String, _MissingKind> _kMissingSchemaCodes = {
  // PostgREST: the table is not in the schema cache. This is the one the
  // Devotionals screen hit.
  'PGRST205': _MissingKind.table,
  // PostgREST: the RPC is not in the schema cache — `feed_for`, `admin_metrics`
  // and friends exist in this repo and not in that database.
  'PGRST202': _MissingKind.function,
  // Raw Postgres: undefined table.
  '42P01': _MissingKind.table,
  // Raw Postgres: undefined column. The `place_name` failure, exactly.
  '42703': _MissingKind.column,
};

/// What someone who is not a developer reads. It promises nothing, blames
/// nobody, and above all does not tell them to check a connection that is
/// working perfectly well.
const String _releaseMissingMessage = "This isn't available right now.";

/// The one actionable line: which file to run.
const String _migrationHint =
    "A database migration hasn't been applied. "
    'See supabase/migrations/ and the README.';

/// A missing table, column or function, described for both audiences at once.
///
/// [AppErrorInfo.message] is developer-facing in debug and neutral in release;
/// [AppErrorInfo.details] always carries the object's name and the next step,
/// because details are opt-in — nobody reads them by accident — and a support
/// round trip that starts with the migration filename is a support round trip
/// that ends immediately.
///
/// [AppErrorInfo.isTransport] stays false. Nothing here is the network.
AppErrorInfo _missingSchema(
  PostgrestException error, {
  required String code,
  required _MissingKind kind,
  required String diagnostic,
  required String details,
}) {
  final object = _missingObjectName(error.message);
  final migration = migrationForObject(object);

  final named = object == null ? '' : ' (${kind.label}: $object)';
  return AppErrorInfo(
    message: kDebugMode
        ? '${kind.debugMessage}$named'
        : _releaseMissingMessage,
    code: 'postgres:$code',
    diagnostic:
        'schema missing — ${kind.label} ${object ?? 'unknown'} '
        '${migration == null ? '' : '→ ${migrationPath(migration)} '}| $diagnostic',
    details: [
      details,
      '',
      'missing ${kind.label}: ${object ?? 'unknown'}',
      _migrationHint,
      // Only in debug: naming the file is developer guidance, and on a shipped
      // build it is the internals of the server leaking into a dialog anyone
      // can open.
      if (kDebugMode && migration != null)
        'apply: ${migrationPath(migration)}',
      if (kDebugMode && migration != null)
        "then reload PostgREST's cache: NOTIFY pgrst, 'reload schema';",
    ].join('\n'),
    isMapped: true,
    isSchemaMissing: true,
  );
}

/// The name of the object a Postgres or PostgREST message is complaining about.
///
/// Three shapes, because these four codes come from two different programs:
///
/// * PostgREST — `Could not find the table 'public.devotionals' in the schema
///   cache`, single-quoted;
/// * Postgres — `column "place_name" of relation "activities" does not exist`,
///   double-quoted, offending name first;
/// * PostgREST again — `Could not find the function public.feed_for(viewer) in
///   the schema cache`, unquoted.
///
/// Returns null rather than guessing when none of the three match. An unnamed
/// object still gets the migration hint; a wrongly named one would send someone
/// to the wrong file.
String? _missingObjectName(String message) {
  final single = RegExp(r"'([^']+)'").firstMatch(message);
  if (single != null) return single.group(1);
  final double = RegExp(r'"([^"]+)"').firstMatch(message);
  if (double != null) return double.group(1);
  final bare = RegExp(r'\b(?:public|auth)\.([A-Za-z_][A-Za-z0-9_]*)')
      .firstMatch(message);
  return bare?.group(1);
}

/// A genuine transport failure: the request never reached the server, or never
/// came back. Nothing else is allowed to claim a connection problem.
///
/// `SocketException` is matched by name rather than by type on purpose — it
/// lives in `dart:io`, which this app cannot import while it also builds for
/// web. `ClientException` and [TimeoutException] cover the rest, and
/// Supabase's own retryable auth failure is the network by another name.
bool _isTransport(Object error) {
  if (error is TimeoutException || error is ClientException) return true;
  if (error is AuthRetryableFetchException) return true;
  final type = error.runtimeType.toString();
  return type == 'SocketException' || type == 'HandshakeException';
}
