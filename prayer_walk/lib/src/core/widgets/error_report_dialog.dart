import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Everything needed to diagnose a failure from the device screen alone.
///
/// The point of carrying [code] and [details] alongside [message] is that a
/// failure can be read off the emulator without going back to the terminal —
/// and copied out of it verbatim when it does need to travel.
class ErrorReport {
  /// [title] is a heading, [message] the consequence. They are never allowed to
  /// be the same sentence.
  ///
  /// A dialog headed "That didn't load" whose body reads "That didn't load."
  /// has spent two lines saying one thing and left the person no better off —
  /// which is what this dialog shipped doing. Callers should pass a real pair,
  /// and most now do; this constructor is the floor under them, so a caller
  /// that passes one string for both gets the generic heading back rather than
  /// an echo. Enforced here rather than at the call sites because there is no
  /// version of this that is worth re-checking in nine screens.
  factory ErrorReport({
    required String tag,
    required String code,
    required String message,
    String title = defaultTitle,
    String? details,
    StackTrace? stackTrace,
  }) {
    final heading = _isSameSentence(title, message)
        // Falling back to the generic heading only helps if it is not itself
        // the echo. It never has been; this is here so the rule holds without
        // depending on that.
        ? (_isSameSentence(defaultTitle, message) ? 'Error details' : defaultTitle)
        : title;
    return ErrorReport._(
      tag: tag,
      code: code,
      message: message,
      title: heading,
      details: details,
      stackTrace: stackTrace,
    );
  }

  const ErrorReport._({
    required this.tag,
    required this.code,
    required this.message,
    required this.title,
    this.details,
    this.stackTrace,
  });

  /// The heading used when a caller has nothing more specific to say.
  static const String defaultTitle = 'What went wrong';

  /// Two strings that would read as the same line on screen. Trailing
  /// punctuation and case are the only differences people write by accident.
  static bool _isSameSentence(String a, String b) {
    String normalise(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'[.!\s]+$'), '');
    return normalise(a) == normalise(b);
  }

  /// The dialog's heading. Names the thing that failed — this report is shown
  /// for saves and posts as well as for sign-in.
  final String title;

  /// Which subsystem reported it, e.g. `GoogleAuth`.
  final String tag;

  /// The machine-readable cause, e.g. `unknownError`. This is the field that
  /// maps onto a fix.
  final String code;

  /// One friendly line for the person holding the phone.
  final String message;

  /// Raw exception text — the developer-facing detail.
  final String? details;

  final StackTrace? stackTrace;

  /// The clipboard payload: everything, in one block, ready to paste.
  String toClipboardText() {
    final buffer = StringBuffer()
      ..writeln('[$tag] $code')
      ..writeln(message);
    if (details != null) buffer.writeln('\ndetails: $details');
    if (stackTrace != null) buffer.writeln('\nstack:\n$stackTrace');
    return buffer.toString();
  }
}

/// Shows [report] as a plain, self-contained dialog.
///
/// Deliberately theme-independent — every colour is literal rather than read
/// from [ColorScheme]. This dialog exists to report failures that may have
/// happened while the app was half-initialized, so it must not depend on the
/// very theme, providers or router that might be the thing that broke.
Future<void> showErrorReport(BuildContext context, ErrorReport report) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ErrorReportDialog(report: report),
  );
}

class _ErrorReportDialog extends StatelessWidget {
  const _ErrorReportDialog({required this.report});

  final ErrorReport report;

  static const _surface = Color(0xFF1F1F1F);
  static const _danger = Color(0xFFFF6B6B);
  static const _body = Color(0xFFEDEDED);
  static const _muted = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: _danger, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.title,
                      style: const TextStyle(
                        color: _danger,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                report.message,
                style: const TextStyle(color: _body, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),
              // The code is the diagnostic key — selectable so it can be read
              // off or copied on its own.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  '[${report.tag}] ${report.code}',
                  style: const TextStyle(
                    color: Color(0xFFFFD479),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (report.details != null) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      report.details!,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.4,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Wrap, not Row: two labelled buttons are wider than a narrow
              // phone at a large text setting, and the one dialog that exists
              // to report failures must not produce one of its own.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: report.toClipboardText()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Details copied.')),
                      );
                    },
                    child: const Text(
                      'Copy details',
                      style: TextStyle(color: Color(0xFF8AB4F8)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: _body),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
