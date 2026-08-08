import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/diagnostics/schema_preflight.dart';
import 'src/core/theme/app_typography.dart';
import 'src/core/utils/app_haptics.dart';
import 'src/core/utils/app_logger.dart';
// Temporary — see [_logSigningCertificates].
import 'src/features/auth/data/signing_certificate.dart';
import 'src/features/scripture/domain/bible_translation.dart';
import 'src/features/scripture/presentation/scripture_credits.dart';

/// Three nets, because an uncaught error can escape by three different routes
/// and any one of them left open means a failure that reports nothing at all:
///
/// * [FlutterError.onError] — errors raised inside the framework (build, layout,
///   paint, gesture callbacks).
/// * [PlatformDispatcher.instance.onError] — async errors that escape the
///   widget tree entirely, including anything thrown from a platform channel
///   callback. This is the one that catches a failing plugin call.
/// * [runZonedGuarded] — everything else running in the app's zone.
///
/// All three funnel into `[PW-FATAL]`, which is the single string to grep for.
/// None of them swallow: `presentError` still runs in debug so the red screen
/// and the usual console dump are unchanged.
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Both bundled families are OFL 1.1, which requires the licence to travel
      // with them. Registered here so it reaches the app's licence page whether
      // or not startup goes on to succeed.
      AppTypography.registerFontLicences();

      // The scripture notices, on the same page and for the same reason: a
      // translation's credit line is a condition of quoting it, and it has to
      // reach the licence page whether or not startup goes on to succeed.
      registerScriptureLicences(
        BibleTranslation.of(AppConfig.scriptureTranslation),
      );

      // Read once, so every later call site can fire synchronously. Failure
      // leaves feedback on, which is the default anyone would expect.
      await AppHaptics.restore();

      FlutterError.onError = (details) {
        AppLogger.fatal(
          'FlutterError.onError${details.context == null ? '' : ' (${details.context})'}',
          details.exception,
          details.stack,
        );
        if (kDebugMode) FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.fatal('PlatformDispatcher.onError', error, stack);
        // Handled — reported above, and swallowing it here would be the exact
        // silence this instrumentation exists to remove.
        return true;
      };

      // TEMPORARY DIAGNOSTIC SCAFFOLDING — remove with the rest of `PW-SIGN`
      // once the Play Store sign-in failure is resolved.
      //
      // Deliberately before [AppConfig.validate]: the fingerprint is worth
      // having even from a build whose config is broken enough to fail
      // validation and never reach the sign-in screen at all. It cannot
      // prevent startup — [readSigningCertificates] does not throw — and the
      // only delay it adds is one platform-channel round trip, on builds that
      // asked for it.
      if (AppConfig.diagnosticsEnabled) await _logSigningCertificates();

      try {
        // Everything runtime-configurable comes from env.json via
        // `--dart-define-from-file=env.json`. Validate first so a missing define
        // fails with a readable, on-screen message instead of a blank white
        // screen or an opaque network error on the first request.
        AppConfig.validate();

        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabasePublishableKey,
        );
      } catch (error, stackTrace) {
        // Startup failed before the app could mount. Show the reason on screen
        // rather than leaving a blank canvas the developer has to guess at.
        AppLogger.error('PW-STARTUP', 'Startup failed', error, stackTrace);
        runApp(StartupErrorApp(error: error, stackTrace: stackTrace));
        return;
      }

      // Deliberately not awaited. It asks the database whether it has the
      // tables and RPCs this build expects, which is worth knowing at startup
      // and never worth waiting for — a preflight that delays the first frame
      // has become a worse problem than the drift it reports. Debug and
      // internal builds only; a no-op in release.
      unawaited(SchemaPreflight.run());

      runApp(const ProviderScope(child: PrayerWalkApp()));
    },
    (error, stackTrace) => AppLogger.fatal('runZonedGuarded', error, stackTrace),
  );
}

/// TEMPORARY DIAGNOSTIC SCAFFOLDING — remove once the Play Store Google
/// sign-in failure is resolved.
///
/// Puts the installed package's signing fingerprints in the log, so a build
/// that can reach `adb logcat` needs no further interaction to answer the
/// question. The screen is the real deliverable — the device under test has
/// not been reachable over adb — but a log line costs nothing and, unlike the
/// screen, it lands before anything else can go wrong.
///
/// The level is chosen rather than fixed: [AppLogger] drops debug/info/warn in
/// release (see `AppLogger._write`), and this diagnostic exists *for* a release
/// build, so in release it goes out at `error` — the wrong severity, but the
/// only one that reaches logcat at all. The tag says what it really is.
Future<void> _logSigningCertificates() async {
  final certificates = await readSigningCertificates();
  final message = 'installed signing certificate(s): ${certificates.describe()}';
  if (!kDebugMode) {
    AppLogger.error(signingCertificateTag, message);
  } else if (certificates.isAvailable) {
    AppLogger.info(signingCertificateTag, message);
  } else {
    AppLogger.warn(signingCertificateTag, message);
  }
}

/// A deliberately plain, dependency-free screen shown when startup fails.
///
/// It must not touch the app's theme, router, or providers — those are exactly
/// what may have failed to initialize. Its only job is to make a startup
/// failure legible instead of rendering a blank white screen. The stack trace
/// is only shown in debug builds.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1B1B1B),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Color(0xFFFF6B6B),
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Prayer Walk could not start',
                    style: TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '$error',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  if (kDebugMode && stackTrace != null) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Stack trace (debug only):',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      '$stackTrace',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
