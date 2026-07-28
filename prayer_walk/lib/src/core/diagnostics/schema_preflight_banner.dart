import 'package:flutter/material.dart';

import 'schema_manifest.dart';
import 'schema_preflight.dart';

/// A dismissible strip over the app when the database is behind the code.
///
/// The log block from [SchemaPreflight] is the real report; this is so the
/// finding is not missed by whoever is looking at the phone rather than the
/// terminal — which, on a physical device, is usually the situation.
///
/// It renders nothing at all unless the preflight is enabled and actually found
/// something, so wrapping the app in it costs a single null check in release.
/// Deliberately theme-independent, like the error dialog: this has to be
/// legible on a build whose theme may itself be part of what is wrong.
class SchemaPreflightBanner extends StatefulWidget {
  const SchemaPreflightBanner({super.key, required this.child});

  final Widget child;

  @override
  State<SchemaPreflightBanner> createState() => _SchemaPreflightBannerState();
}

class _SchemaPreflightBannerState extends State<SchemaPreflightBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (!SchemaPreflight.isEnabled) return widget.child;

    return ValueListenableBuilder<SchemaPreflightReport?>(
      valueListenable: SchemaPreflight.report,
      builder: (context, report, child) {
        if (report == null || !report.hasMissing || _dismissed) return child!;
        return Directionality(
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          child: Stack(
            children: [
              child!,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _Banner(
                    report: report,
                    onDismiss: () => setState(() => _dismissed = true),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.report, required this.onDismiss});

  final SchemaPreflightReport report;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final missing = report.missing;
    final files = report.missingMigrations;

    return Material(
      color: const Color(0xFF3A2A00),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.storage_rounded, color: Color(0xFFFFD479), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Database is behind this build — '
                    '${missing.length} object${missing.length == 1 ? '' : 's'} missing',
                    style: const TextStyle(
                      color: Color(0xFFFFD479),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    [
                      missing.map((p) => p.name).join(', '),
                      if (files.isNotEmpty)
                        'Run: ${files.map(migrationPath).join(' → ')}',
                    ].join('\n'),
                    style: const TextStyle(
                      color: Color(0xFFE8DCC0),
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFFE8DCC0), size: 18),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
