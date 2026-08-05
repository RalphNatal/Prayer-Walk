import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/auth/domain/google_config_diagnostics.dart';

/// [GoogleConfigDiagnostics] can't prove a client ID is registered anywhere —
/// only Google Cloud Console knows that — but it can catch the two things a
/// plain string comparison can: a value that isn't shaped like a client ID at
/// all, and two client IDs issued under different Google Cloud projects,
/// which is otherwise invisible from either ID read on its own.
void main() {
  group('hasPlausibleShape', () {
    test('a well-formed client ID passes', () {
      expect(
        GoogleConfigDiagnostics.hasPlausibleShape(
          '123456789012-abc123def456.apps.googleusercontent.com',
        ),
        isTrue,
      );
    });

    test('empty fails', () {
      expect(GoogleConfigDiagnostics.hasPlausibleShape(''), isFalse);
    });

    test('missing the suffix fails', () {
      expect(
        GoogleConfigDiagnostics.hasPlausibleShape('123456789012-abc123def456'),
        isFalse,
      );
    });

    test('a non-numeric prefix fails', () {
      expect(
        GoogleConfigDiagnostics.hasPlausibleShape(
          'not-a-project-number.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });

    test('no dash at all fails', () {
      expect(
        GoogleConfigDiagnostics.hasPlausibleShape(
          '123456789012.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });
  });

  group('projectNumberPrefix', () {
    test('reads the digits before the first dash', () {
      expect(
        GoogleConfigDiagnostics.projectNumberPrefix(
          '123456789012-abc123def456.apps.googleusercontent.com',
        ),
        '123456789012',
      );
    });

    test('null when there is no dash', () {
      expect(
        GoogleConfigDiagnostics.projectNumberPrefix(
          '123456789012.apps.googleusercontent.com',
        ),
        isNull,
      );
    });

    test('null for an empty string', () {
      expect(GoogleConfigDiagnostics.projectNumberPrefix(''), isNull);
    });

    test(
      'two IDs from different Google Cloud projects surface different prefixes',
      () {
        const web = '111111111111-webhash.apps.googleusercontent.com';
        const ios = '222222222222-ioshash.apps.googleusercontent.com';
        expect(
          GoogleConfigDiagnostics.projectNumberPrefix(web),
          isNot(GoogleConfigDiagnostics.projectNumberPrefix(ios)),
        );
      },
    );

    test('two IDs from the same project share a prefix', () {
      const web = '111111111111-webhash.apps.googleusercontent.com';
      const ios = '111111111111-ioshash.apps.googleusercontent.com';
      expect(
        GoogleConfigDiagnostics.projectNumberPrefix(web),
        GoogleConfigDiagnostics.projectNumberPrefix(ios),
      );
    });
  });
}
