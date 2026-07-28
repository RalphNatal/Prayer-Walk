import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Type for Prayer Walk.
///
/// Two families, strictly divided:
/// * **Fraunces** (soft crafted serif) — display sizes, screen titles and big
///   stat numerals only. It carries the devotional warmth; it never sets body
///   copy, where it would read like a newspaper.
/// * **Hanken Grotesk** (humanist sans) — everything else, legible down to 12.
///
/// Both are bundled as assets rather than fetched at runtime. They used to come
/// from `google_fonts`, which downloads over HTTP on first launch and caches —
/// meaning a first run in a dead zone rendered the entire app in the system
/// fallback and the identity simply vanished. This app is used outdoors, often
/// with no signal; its own typeface cannot be a network request.
///
/// Only the weights the theme actually asks for are shipped: Fraunces 600, and
/// Hanken Grotesk 400/500/600/700. Every additional face is real download size
/// for glyphs nothing draws.
abstract final class AppTypography {
  /// Lining, fixed-width figures. Stat readouts must not jitter as they change,
  /// so every numeral that updates uses this.
  static const List<FontFeature> tabular = [
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  /// The family names declared in `pubspec.yaml`. Nothing resolves a family any
  /// other way.
  static const String displayFamily = 'Fraunces';
  static const String textFamily = 'HankenGrotesk';

  /// Both families are SIL Open Font License 1.1, which requires the licence to
  /// travel with the fonts. This puts them on the app's own licence page
  /// (`showLicensePage`) alongside every package licence Flutter collects.
  ///
  /// Called from `main` before `runApp`. The callback is lazy — nothing is read
  /// off disk unless someone opens the licence page.
  static void registerFontLicences() {
    LicenseRegistry.addLicense(() async* {
      for (final entry in const {
        'Fraunces': 'assets/fonts/OFL-Fraunces.txt',
        'Hanken Grotesk': 'assets/fonts/OFL-HankenGrotesk.txt',
      }.entries) {
        yield LicenseEntryWithLineBreaks(
          [entry.key],
          await rootBundle.loadString(entry.value),
        );
      }
    });
  }

  static TextStyle display(TextStyle base) =>
      base.copyWith(fontFamily: displayFamily);

  static TextStyle text(TextStyle base) =>
      base.copyWith(fontFamily: textFamily);

  static TextStyle _display(
    double size, {
    FontWeight weight = FontWeight.w600,
    double height = 1.18,
    double letterSpacing = -0.4,
    Color? color,
  }) => display(
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    ),
  );

  static TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    double letterSpacing = 0,
    Color? color,
  }) => text(
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    ),
  );

  /// A large stat numeral: Fraunces, tabular, tight.
  static TextStyle statDisplay(Color color, {double size = 40}) =>
      _display(
        size,
        height: 1.0,
        letterSpacing: -1,
        color: color,
      ).copyWith(fontFeatures: tabular);

  /// The standard stat readout used by StatTile and the live screen.
  static TextStyle statValue(Color color, {double size = 24}) =>
      _display(
        size,
        height: 1.05,
        letterSpacing: -0.5,
        color: color,
      ).copyWith(fontFeatures: tabular);

  /// Inline figures inside sentences and captions (sans, still tabular).
  static TextStyle statInline(Color color, {double size = 14}) => _text(
    size,
    weight: FontWeight.w600,
    height: 1.2,
    color: color,
  ).copyWith(fontFeatures: tabular);

  /// Scale: display 32/28/24 · title 20/18/16 · body 16/14 · caption 12.
  static TextTheme textTheme(Color onSurface, Color muted) => TextTheme(
    displayLarge: _display(32, height: 1.14, letterSpacing: -0.6, color: onSurface),
    displayMedium: _display(28, letterSpacing: -0.5, color: onSurface),
    displaySmall: _display(24, height: 1.22, letterSpacing: -0.3, color: onSurface),

    // Headlines stay in Fraunces — these are screen titles, not running text.
    headlineLarge: _display(24, height: 1.22, letterSpacing: -0.3, color: onSurface),
    headlineMedium: _display(20, height: 1.25, letterSpacing: -0.2, color: onSurface),
    headlineSmall: _display(18, height: 1.3, letterSpacing: -0.1, color: onSurface),

    titleLarge: _text(20, weight: FontWeight.w600, height: 1.25, letterSpacing: -0.2, color: onSurface),
    titleMedium: _text(18, weight: FontWeight.w600, height: 1.3, letterSpacing: -0.1, color: onSurface),
    titleSmall: _text(16, weight: FontWeight.w600, height: 1.35, color: onSurface),

    bodyLarge: _text(16, height: 1.5, color: onSurface),
    bodyMedium: _text(14, height: 1.45, color: onSurface),
    bodySmall: _text(12, height: 1.4, color: muted),

    labelLarge: _text(15, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.1, color: onSurface),
    labelMedium: _text(13, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.1, color: muted),
    labelSmall: _text(12, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.4, color: muted),
  );
}
