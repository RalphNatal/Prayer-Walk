import 'package:flutter/material.dart';

/// "First Light" — dawn on the trail.
///
/// The named tokens below are the brand palette. A few *derived* tokens sit
/// alongside them (suffixed `Text`, `Light`, `Deep`): the brand values are
/// tuned for surfaces and marks, and some of them do not clear WCAG AA when
/// used as small text. Rather than bend the brand, we derive an accessible
/// sibling and use it wherever the colour carries type.
abstract final class AppColors {
  // ---------------------------------------------------------------- brand ---

  /// Deep evergreen. App bars, brand marks, surfaces-on-dark.
  static const Color pine = Color(0xFF223D30);

  /// Supporting green. Selected states, links, secondary UI.
  static const Color moss = Color(0xFF3E6B4F);

  /// The kindled light. Primary CTA, live pulse, trail highlight. Used sparingly.
  static const Color amber = Color(0xFFE3A24A);

  /// Warm light surface — cards, sheets, inputs.
  static const Color parchment = Color(0xFFF3EEE4);

  /// Light-theme app background, a shade deeper than [parchment] so cards lift.
  static const Color canvas = Color(0xFFE7E1D4);

  /// Primary text on light. Near-black with a green undertone, never pure black.
  static const Color ink = Color(0xFF1A2620);

  /// Muted token for inactive marks and hairline-adjacent UI.
  static const Color stone = Color(0xFF8A897E);

  /// Dividers, inactive icons, hairlines.
  static const Color mist = Color(0xFFD9D5C8);

  // -------------------------------------------------------------- derived ---

  /// AA-compliant secondary text on [canvas] (4.7:1) and [parchment] (5.3:1).
  /// [stone] itself only reaches 2.7:1, so it never carries small type.
  static const Color stoneText = Color(0xFF63625A);

  /// Border colour that clears the 3:1 non-text contrast floor on [canvas].
  static const Color outlineLight = Color(0xFF7C7A6D);

  // ----------------------------------------------------------------- dark ---

  /// Near-black forest — dark app background.
  static const Color canvasDark = Color(0xFF12201A);

  /// Raised surface on dark — cards, sheets, inputs.
  static const Color surfaceDark = Color(0xFF1C2B23);
  static const Color surfaceDarkLowest = Color(0xFF0D1813);
  static const Color surfaceDarkLow = Color(0xFF16241D);
  static const Color surfaceDarkHigh = Color(0xFF23342A);
  static const Color surfaceDarkHighest = Color(0xFF2B3E33);

  /// Warm off-white primary text on dark (12.3:1 on [surfaceDark]).
  static const Color inkDark = Color(0xFFEDEAE0);

  /// Moss, lightened so it clears AA on the dark ground (5.2:1).
  static const Color mossLight = Color(0xFF6FA57F);
  static const Color mossLighter = Color(0xFF8FBE9E);

  /// Muted text on dark (5.9:1 on [surfaceDark]).
  static const Color stoneTextDark = Color(0xFF9AA79C);

  static const Color outlineDark = Color(0xFF6E7F72);
  static const Color mistDark = Color(0xFF2E4034);

  // ---------------------------------------------------------- containers ---

  static const Color pineContainer = Color(0xFFCFDDD0);
  static const Color mossContainer = Color(0xFFDCE7DC);
  static const Color amberContainer = Color(0xFFF6E2C2);
  static const Color onAmberContainer = Color(0xFF4A3208);

  static const Color pineContainerDark = Color(0xFF2C4B38);
  static const Color mossContainerDark = Color(0xFF2A4534);
  static const Color amberContainerDark = Color(0xFF5C4114);
  static const Color onAmberContainerDark = Color(0xFFF7DDB4);

  // --------------------------------------------------------------- status ---

  static const Color emberLight = Color(0xFFA5402F);
  static const Color emberDark = Color(0xFFEE9C8D);
  static const Color emberContainerLight = Color(0xFFF6DCD5);
  static const Color onEmberContainerLight = Color(0xFF4A150C);
  static const Color emberContainerDark = Color(0xFF6E2418);
  static const Color onEmberContainerDark = Color(0xFFFBDAD2);

  /// Published / resolved / healthy.
  static const Color verdantLight = Color(0xFF2F6B45);
  static const Color verdantDark = Color(0xFF7EC594);

  /// Draft / pending / needs attention.
  static const Color ochreLight = Color(0xFF8A5A11);
  static const Color ochreDark = Color(0xFFE3B872);

  // ------------------------------------------------------------ schemes ---

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: pine,
    onPrimary: parchment,
    primaryContainer: pineContainer,
    onPrimaryContainer: pine,
    secondary: moss,
    onSecondary: parchment,
    secondaryContainer: mossContainer,
    onSecondaryContainer: Color(0xFF1B3527),
    tertiary: amber,
    onTertiary: ink,
    tertiaryContainer: amberContainer,
    onTertiaryContainer: onAmberContainer,
    error: emberLight,
    onError: Color(0xFFFFF3EF),
    errorContainer: emberContainerLight,
    onErrorContainer: onEmberContainerLight,
    surface: canvas,
    onSurface: ink,
    surfaceDim: Color(0xFFDBD5C7),
    surfaceBright: Color(0xFFFBF8F1),
    surfaceContainerLowest: Color(0xFFFBF8F1),
    surfaceContainerLow: parchment,
    surfaceContainer: Color(0xFFEDE7DB),
    surfaceContainerHigh: canvas,
    surfaceContainerHighest: Color(0xFFDFD9CB),
    onSurfaceVariant: stoneText,
    outline: outlineLight,
    outlineVariant: mist,
    inverseSurface: pine,
    onInverseSurface: parchment,
    inversePrimary: mossLight,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: mossLight,
    onPrimary: Color(0xFF0B1A12),
    primaryContainer: pineContainerDark,
    onPrimaryContainer: Color(0xFFC6E3CE),
    secondary: mossLighter,
    onSecondary: Color(0xFF0B1A12),
    secondaryContainer: mossContainerDark,
    onSecondaryContainer: Color(0xFFCDE6D4),
    tertiary: amber,
    onTertiary: Color(0xFF2A1B05),
    tertiaryContainer: amberContainerDark,
    onTertiaryContainer: onAmberContainerDark,
    error: emberDark,
    onError: Color(0xFF4A150C),
    errorContainer: emberContainerDark,
    onErrorContainer: onEmberContainerDark,
    surface: canvasDark,
    onSurface: inkDark,
    surfaceDim: canvasDark,
    surfaceBright: Color(0xFF33463A),
    surfaceContainerLowest: surfaceDarkLowest,
    surfaceContainerLow: surfaceDarkLow,
    surfaceContainer: surfaceDark,
    surfaceContainerHigh: surfaceDarkHigh,
    surfaceContainerHighest: surfaceDarkHighest,
    onSurfaceVariant: stoneTextDark,
    outline: outlineDark,
    outlineVariant: mistDark,
    inverseSurface: inkDark,
    onInverseSurface: ink,
    inversePrimary: pine,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}
