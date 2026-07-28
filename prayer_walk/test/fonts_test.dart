import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';

/// Fonts are bundled, not fetched. This is the assertion that keeps them that
/// way: a `google_fonts` regression, or a pubspec `fonts:` block that loses a
/// weight, both show up here rather than as a wrong-looking release build.
void main() {
  testWidgets('every theme style resolves to a bundled family', (tester) async {
    final text = AppTheme.light().textTheme;

    // Display and headline are Fraunces; everything else is Hanken Grotesk.
    for (final style in [
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
    ]) {
      expect(style?.fontFamily, AppTypography.displayFamily);
    }
    for (final style in [
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(style?.fontFamily, AppTypography.textFamily);
    }
  });

  testWidgets('the bundled font assets are loadable and non-empty', (
    tester,
  ) async {
    // Reads the real asset bundle. A missing or mis-pathed face in pubspec.yaml
    // fails here instead of silently falling back to the system font on device.
    for (final asset in const [
      'assets/fonts/Fraunces-SemiBold.ttf',
      'assets/fonts/HankenGrotesk-Regular.ttf',
      'assets/fonts/HankenGrotesk-Medium.ttf',
      'assets/fonts/HankenGrotesk-SemiBold.ttf',
      'assets/fonts/HankenGrotesk-Bold.ttf',
      'assets/fonts/OFL-Fraunces.txt',
      'assets/fonts/OFL-HankenGrotesk.txt',
    ]) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(1000), reason: '$asset is empty');
    }
  });

  testWidgets('both font licences reach the licence registry', (tester) async {
    AppTypography.registerFontLicences();
    final families = <String>[];
    await for (final entry in LicenseRegistry.licenses) {
      families.addAll(entry.packages);
    }
    expect(families, contains('Fraunces'));
    expect(families, contains('Hanken Grotesk'));
  });
}
