import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/auth/domain/auth_diagnostics_verdict.dart';

/// [AuthDiagnosticsVerdict] turns the diagnostic screen's raw evidence into
/// one headline. These tests exercise it directly, without a widget harness
/// or a real Google/Supabase round trip, by feeding it every combination of
/// outcome the screen can actually produce.
void main() {
  group('headline', () {
    test("hasn't run yet", () {
      expect(
        AuthDiagnosticsVerdict.headline(probe: GoogleProbeOutcome.notRun),
        contains('Run all'),
      );
    });

    test('the sheet was dismissed', () {
      expect(
        AuthDiagnosticsVerdict.headline(probe: GoogleProbeOutcome.cancelled),
        contains('dismissed'),
      );
    });

    test('refused surfaces the classified reason verbatim', () {
      expect(
        AuthDiagnosticsVerdict.headline(
          probe: GoogleProbeOutcome.refused,
          refusalReason: 'a specific, already-classified reason',
        ),
        'a specific, already-classified reason',
      );
    });

    test('refused with no reason still says something', () {
      expect(
        AuthDiagnosticsVerdict.headline(probe: GoogleProbeOutcome.refused),
        isNotEmpty,
      );
    });

    test('issued but the aud claim was undecodable names that gap', () {
      expect(
        AuthDiagnosticsVerdict.headline(
          probe: GoogleProbeOutcome.issued,
          audMatches: null,
        ),
        contains('Token audience'),
      );
    });

    test('issued with a mismatched aud names the wrong client ID', () {
      final result = AuthDiagnosticsVerdict.headline(
        probe: GoogleProbeOutcome.issued,
        audMatches: false,
      );
      expect(result, contains('GOOGLE_WEB_CLIENT_ID is wrong'));
    });

    test('issued, aud matches, Supabase never tried', () {
      final result = AuthDiagnosticsVerdict.headline(
        probe: GoogleProbeOutcome.issued,
        audMatches: true,
      );
      expect(result, contains("wasn't handed to Supabase"));
    });

    test('issued, aud matches, Supabase rejected — the split the maintainer '
        "couldn't see before", () {
      final result = AuthDiagnosticsVerdict.headline(
        probe: GoogleProbeOutcome.issued,
        audMatches: true,
        supabaseOutcome: SupabaseAcceptOutcome.rejected,
      );
      expect(result, contains('Supabase rejected it'));
      expect(result, contains('Auth → Providers → Google'));
    });

    test('issued, aud matches, Supabase accepted — everything passed', () {
      final result = AuthDiagnosticsVerdict.headline(
        probe: GoogleProbeOutcome.issued,
        audMatches: true,
        supabaseOutcome: SupabaseAcceptOutcome.accepted,
      );
      expect(result, 'Everything passed.');
    });
  });

  group('classifyRefusal', () {
    test('a description naming 28444 points at the developer console', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'unknownError',
        description: '[28444] Developer console is not set up correctly.',
      );
      expect(reason, contains('Test user'));
    });

    test('a description naming the developer console directly, without the '
        'numeric code, is still recognised', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'unknownError',
        description: 'Developer console is not set up correctly for this '
            'application.',
      );
      expect(reason, contains('Test user'));
    });

    test('a no-account description points at the device instead', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'unknownError',
        description: 'No credentials available on this device.',
      );
      expect(reason, contains('Add a'));
      expect(reason, isNot(contains('Test user')));
    });

    test('an ambiguous unknownError names both, without guessing', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'unknownError',
        description: null,
      );
      expect(reason, contains('developer console'));
      expect(reason, contains('device'));
    });

    test('clientConfigurationError names the client ID directly', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'clientConfigurationError',
      );
      expect(reason, contains('GOOGLE_WEB_CLIENT_ID'));
    });

    test('providerConfigurationError points at Play services', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'providerConfigurationError',
      );
      expect(reason, contains('Play services'));
    });

    test('uiUnavailable is classified the same as providerConfigurationError', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(code: 'uiUnavailable');
      expect(reason, contains('Play services'));
    });

    test('userMismatch names the account conflict', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(code: 'userMismatch');
      expect(reason, contains('already signed in'));
    });

    test('an unrecognised code still returns a non-empty, honest fallback', () {
      final reason = AuthDiagnosticsVerdict.classifyRefusal(
        code: 'someFutureCode',
      );
      expect(reason, contains('someFutureCode'));
    });
  });
}
