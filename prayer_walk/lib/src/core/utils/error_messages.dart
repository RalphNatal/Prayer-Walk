import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        AuthRetryableFetchException,
        PostgrestException,
        StorageException;

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

  ErrorReport toReport({
    required String tag,
    String title = 'What went wrong',
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

  // The message is the caller's fallback unless the code says something
  // definite. Every branch below is a code Postgres or PostgREST sent.
  final (String message, bool mapped) = switch (code) {
    // Undefined column: the app is asking for something this database does not
    // have — a migration that has not been applied. Naming the column is what
    // turns "it didn't save" into a one-line fix.
    '42703' => (
      'This app is out of date with the server. '
          '(schema: ${_quotedName(error.message) ?? 'unknown column'})',
      true,
    ),
    '42P01' => ("Something's missing on the server. Please contact support.", true),
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

/// The first `"quoted"` identifier in a Postgres message — for 42703 that is
/// the column it could not find.
String? _quotedName(String message) {
  final match = RegExp(r'"([^"]+)"').firstMatch(message);
  return match?.group(1);
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
