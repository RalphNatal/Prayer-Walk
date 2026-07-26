import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Applies one of the two families to a base style.
typedef FontResolver = TextStyle Function(TextStyle base);

/// Type for Prayer Walk.
///
/// Two families, strictly divided:
/// * **Fraunces** (soft crafted serif) — display sizes, screen titles and big
///   stat numerals only. It carries the devotional warmth; it never sets body
///   copy, where it would read like a newspaper.
/// * **Hanken Grotesk** (humanist sans) — everything else, legible down to 12.
abstract final class AppTypography {
  /// Lining, fixed-width figures. Stat readouts must not jitter as they change,
  /// so every numeral that updates uses this.
  static const List<FontFeature> tabular = [
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  static const String displayFamily = 'Fraunces';
  static const String textFamily = 'HankenGrotesk';

  /// How the families are resolved.
  ///
  /// The default fetches from Google Fonts at runtime and caches on device,
  /// which is fine for this phase but means first paint can wait on a
  /// download. Two callers want to change that:
  ///
  /// * **Production** should bundle both families as assets and call
  ///   [useBundledFonts], so the app renders correctly offline and on first
  ///   launch. (`google_fonts` also picks up bundled assets automatically once
  ///   they are in the pubspec, so either route works.)
  /// * **Tests** call [useBundledFonts] so no test ever reaches for the
  ///   network — `google_fonts` rethrows when it cannot resolve a family, and
  ///   an unhandled failure there would fail every widget test that builds the
  ///   theme.
  static FontResolver display = _googleDisplay;
  static FontResolver text = _googleText;

  static TextStyle _googleDisplay(TextStyle base) =>
      GoogleFonts.fraunces(textStyle: base);

  static TextStyle _googleText(TextStyle base) =>
      GoogleFonts.hankenGrotesk(textStyle: base);

  /// Resolve both families by name, from bundled assets or the platform's
  /// fallback. No network, no async load.
  static void useBundledFonts() {
    display = (base) => base.copyWith(fontFamily: displayFamily);
    text = (base) => base.copyWith(fontFamily: textFamily);
  }

  /// Back to runtime fetching. Mostly here so a test can put things back.
  static void useNetworkFonts() {
    display = _googleDisplay;
    text = _googleText;
  }

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
