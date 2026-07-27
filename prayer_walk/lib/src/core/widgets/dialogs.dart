import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/error_messages.dart';
import 'error_report_dialog.dart';

/// Asks before something irreversible happens.
///
/// [message] states the consequence rather than repeating the question, and
/// [confirmLabel] names the action ("Delete", "Suspend") so the button is
/// readable out of context.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A short confirmation of something that just happened.
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// The one way this app reports a failure.
///
/// It does three things in a fixed order, because the order is the point:
///  1. describes the error from what it actually is — a Postgres code, a
///     transport failure, an unrecognised throw;
///  2. logs type, message and code under [tag] *before* anything is shown, so a
///     failure is on the console even if the person taps the snack bar away;
///  3. shows one honest line, with **Details** for the full report and, when
///     the caller can offer one, a retry.
///
/// [fallback] names the action that failed ("The walk didn't save.") and is
/// used verbatim when the cause is not one [describeFailure] recognises. It
/// must not mention the connection — that sentence is added only for a real
/// transport failure.
///
/// Returns what the error was, for callers that want to log more around it.
AppErrorInfo reportFailure(
  BuildContext context,
  Object error,
  StackTrace stackTrace, {
  required String tag,
  required String fallback,
  String? uniqueMessage,
  VoidCallback? onRetry,
  String retryLabel = 'Retry',
}) {
  final info = describeFailure(
    error,
    fallback: fallback,
    uniqueMessage: uniqueMessage,
  );
  AppLogger.error(
    tag,
    '${info.code} — ${info.diagnostic}',
    error,
    kDebugMode ? stackTrace : null,
  );
  if (context.mounted) {
    showFailureSnackBar(
      context,
      info,
      tag: tag,
      stackTrace: stackTrace,
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }
  return info;
}

/// A failure on screen: the friendly line, plus a way to see what it really
/// was. Never shouts the exception at someone who did not ask for it.
void showFailureSnackBar(
  BuildContext context,
  AppErrorInfo info, {
  required String tag,
  StackTrace? stackTrace,
  VoidCallback? onRetry,
  String retryLabel = 'Retry',
}) {
  final messenger = ScaffoldMessenger.of(context);
  void openDetails() {
    messenger.hideCurrentSnackBar();
    showErrorReport(
      context,
      info.toReport(tag: tag, stackTrace: stackTrace),
    );
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // Longer than a confirmation: this one has to be read, and possibly
        // acted on, before it goes.
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            Expanded(child: Text(info.message)),
            // Inline rather than in the action slot so a retry can have the
            // slot. Both affordances fit because the message shrinks, not the
            // buttons.
            TextButton(
              onPressed: openDetails,
              child: const Text('Details'),
            ),
          ],
        ),
        action: onRetry == null
            ? null
            : SnackBarAction(label: retryLabel, onPressed: onRetry),
      ),
    );
}
