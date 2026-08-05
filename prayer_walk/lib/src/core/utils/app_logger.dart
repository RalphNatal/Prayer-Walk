import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Severity of a log line. Maps onto `dart:developer`'s numeric levels, which
/// are what DevTools filters on.
enum LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warn(900, 'WARN'),
  error(1000, 'ERROR');

  const LogLevel(this.value, this.label);

  final int value;
  final String label;
}

/// A dependency-free tagged logger.
///
/// It writes to two sinks on purpose. [developer.log] carries structure — level,
/// error object, stack — into DevTools, but is easy to miss in a terminal.
/// [debugPrint] is what actually appears in `flutter run`'s console and, on
/// Android, in `adb logcat` under `I/flutter`. A diagnostic nobody can see in
/// the terminal they already have open is not a diagnostic, so every line goes
/// to both.
///
/// Lines are prefixed with a wall-clock timestamp to the millisecond so they can
/// be lined up against `adb logcat`, and with a greppable `[TAG]`.
///
/// Nothing here ever formats a secret. Use [mask] for anything that is or could
/// contain a credential: it reports presence and a short tail, never the value.
abstract final class AppLogger {
  static const _fatalTag = 'PW-FATAL';

  static void debug(String tag, String message) =>
      _write(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _write(LogLevel.info, tag, message);

  static void warn(String tag, String message, [Object? error, StackTrace? s]) =>
      _write(LogLevel.warn, tag, message, error, s);

  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _write(LogLevel.error, tag, message, error, stackTrace);

  /// An uncaught error that reached one of the app-wide handlers in `main.dart`.
  ///
  /// Deliberately its own tag: `[PW-FATAL]` is the single string to grep for
  /// when something died and left nothing else behind.
  static void fatal(String source, Object error, StackTrace? stackTrace) {
    _write(
      LogLevel.error,
      _fatalTag,
      // The object itself travels via the `error` parameter below, which
      // `_write` already redacts to its type in release — baking `$error`
      // into the message text too would bypass that redaction, since the
      // message is never gated at the `error` level.
      '$source → ${error.runtimeType}',
      error,
      stackTrace,
    );
  }

  /// A presence-and-tail description of a config value, safe to log.
  ///
  /// `present (…4b2f9a)` or `EMPTY`. Never the value itself — client IDs, keys
  /// and tokens must not reach the console or logcat, and logcat in particular
  /// is readable by anything on the device.
  static String mask(String? value, {int tail = 6}) {
    if (value == null || value.isEmpty) return 'EMPTY';
    if (value.length <= tail) return 'present (too short to mask)';
    return 'present (…${value.substring(value.length - tail)})';
  }

  static void _write(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    // debug/info/warn are developer chatter; keep all of it out of release
    // consoles. Only `error` (and `fatal`, which is `error` under another
    // name) stays live in release — it is genuinely useful in crash triage.
    if (level != LogLevel.error && !kDebugMode) return;

    final line = '${_timestamp()} [$tag][${level.label}] $message';
    debugPrint(line);
    // The raw error object and its stack trace are printed in full only in
    // debug. In release, a third-party SDK's `Exception.toString()` is not
    // something this app controls the contents of, so an `error`-level call
    // — the one level that always reaches release logcat — reports only the
    // type, never the object itself, and drops the stack trace entirely.
    if (error != null) {
      debugPrint('  └─ error: ${kDebugMode ? error : error.runtimeType}');
    }
    if (stackTrace != null && kDebugMode) {
      debugPrint('  └─ stack:\n$stackTrace');
    }

    developer.log(
      message,
      name: tag,
      level: level.value,
      error: error == null ? null : (kDebugMode ? error : error.runtimeType),
      stackTrace: kDebugMode ? stackTrace : null,
    );
  }

  static String _timestamp() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}
