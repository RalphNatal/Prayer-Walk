/// TEMPORARY DIAGNOSTIC SCAFFOLDING — remove once the Play Store Google
/// sign-in failure is resolved.
///
/// Which signing certificate the *installed* package carries, read from the
/// device via the `prayer_walk/signing` channel in `MainActivity.kt` — see that
/// file for why the question can only be answered by asking the device.
///
/// Nothing in the sign-in path calls this. It exists to be logged at startup
/// and shown on `AuthDiagnosticsScreen`, and both of those only happen when
/// `AppConfig.diagnosticsEnabled` is true.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/app_logger.dart';

const _channel = MethodChannel('prayer_walk/signing');

/// The tag every line of this diagnostic is logged under. Grep for this.
const signingCertificateTag = 'PW-SIGN';

/// The fingerprints of every signer on the installed package.
///
/// Both lists are in the same order and describe the same certificates: index
/// `n` of [sha1] and index `n` of [sha256] are two digests of one signer. More
/// than one entry is not an error — Play's hybrid signing generates more than
/// one key, and finding out how many reach the device is half the point of
/// this.
@immutable
class SigningCertificates {
  const SigningCertificates({
    required this.sha1,
    required this.sha256,
    this.error,
  });

  /// The question couldn't be asked, or couldn't be answered. [reason] is
  /// displayable text, never an exception object — this is shown on screen.
  const SigningCertificates.unavailable(String reason)
    : sha1 = const [],
      sha256 = const [],
      error = reason;

  final List<String> sha1;
  final List<String> sha256;

  /// Why there are no fingerprints, or null if there are.
  final String? error;

  bool get isAvailable => error == null && sha1.isNotEmpty;

  int get signerCount => sha1.length;

  /// A single log line. Fingerprints are printed in full deliberately: they are
  /// public identifiers, shown openly in the Play Console and in Google Cloud
  /// Console, and a masked one would be useless for the comparison this exists
  /// to make.
  String describe() {
    if (error != null) return 'unavailable — $error';
    final buffer = StringBuffer('$signerCount signer(s)');
    for (var i = 0; i < sha1.length; i++) {
      buffer.write('\n  [$i] SHA-1   ${sha1[i]}');
      if (i < sha256.length) buffer.write('\n  [$i] SHA-256 ${sha256[i]}');
    }
    return buffer.toString();
  }
}

/// Asks the device which certificates the installed package is signed with.
///
/// Never throws, and never returns null: a missing channel, an old engine, a
/// platform that has no such concept, or an outright failure on the native side
/// all degrade to [SigningCertificates.unavailable] with a readable reason.
/// This is called before `AppConfig.validate()` on a build that is already known
/// to be broken — it must not be able to make the failure worse.
///
/// Guarded on Android via [defaultTargetPlatform] rather than `Platform.isAndroid`
/// to match the convention the rest of this app already uses (see
/// `location_service.dart`), and because it keeps `dart:io` out of a file that
/// would otherwise be one more thing to make web-safe.
Future<SigningCertificates> readSigningCertificates() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const SigningCertificates.unavailable(
      'Android only — Play App Signing is what this diagnoses.',
    );
  }

  try {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'fingerprints',
    );
    if (result == null) {
      return const SigningCertificates.unavailable(
        'the signing channel returned nothing',
      );
    }

    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      return SigningCertificates.unavailable(error);
    }

    return SigningCertificates(
      sha1: _strings(result['sha1']),
      sha256: _strings(result['sha256']),
    );
  } on MissingPluginException {
    // The channel isn't registered — an older MainActivity, or a hot restart
    // against an engine that predates it. Say so plainly rather than reporting
    // it as a signing problem, which it is not.
    return const SigningCertificates.unavailable(
      'the prayer_walk/signing channel is not registered in this build',
    );
  } catch (error, stack) {
    AppLogger.warn(
      signingCertificateTag,
      'reading signing certificates failed',
      error,
      stack,
    );
    return SigningCertificates.unavailable('${error.runtimeType}');
  }
}

List<String> _strings(Object? value) => value is List
    ? [for (final entry in value) if (entry is String) entry]
    : const [];
