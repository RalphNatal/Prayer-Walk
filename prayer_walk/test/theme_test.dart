import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';

/// Contrast ratio per WCAG 2.1, on the sRGB relative-luminance formula.
///
/// The palette's contrast is a design decision that has to hold as colours are
/// tuned, so it is asserted rather than trusted.
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color color) =>
      0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);

  final la = luminance(a);
  final lb = luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // Resolve families by name instead of fetching them, so the suite never
  // touches the network.
  setUpAll(AppTypography.useBundledFonts);
  tearDownAll(AppTypography.useNetworkFonts);

  /// Material 3's default seed. If it ever shows up, the theme was not applied.
  const materialDefaultPurple = Color(0xFF6750A4);

  group('First Light palette', () {
    test('light theme is the brand, not the Material default', () {
      final theme = AppTheme.light();
      expect(theme.colorScheme.primary, AppColors.pine);
      expect(theme.colorScheme.tertiary, AppColors.amber);
      expect(theme.colorScheme.surface, AppColors.canvas);
      expect(theme.colorScheme.primary, isNot(materialDefaultPurple));
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme lightens moss and keeps amber as the accent', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.primary, AppColors.mossLight);
      expect(theme.colorScheme.tertiary, AppColors.amber);
      expect(theme.colorScheme.surface, AppColors.canvasDark);
      expect(theme.brightness, Brightness.dark);
    });

    test('body and muted text clear WCAG AA in both themes', () {
      final light = AppTheme.light().colorScheme;
      expect(_contrast(light.onSurface, light.surface), greaterThan(4.5));
      expect(_contrast(light.onSurfaceVariant, light.surface), greaterThan(4.5));

      final dark = AppTheme.dark().colorScheme;
      expect(_contrast(dark.onSurface, dark.surface), greaterThan(4.5));
      expect(_contrast(dark.onSurfaceVariant, dark.surface), greaterThan(4.5));
    });

    test('amber carries ink, never white', () {
      final light = AppTheme.light().colorScheme;
      expect(_contrast(light.onTertiary, light.tertiary), greaterThan(4.5));
      expect(
        _contrast(const Color(0xFFFFFFFF), light.tertiary),
        lessThan(3.0),
        reason: 'white on amber is why onTertiary is ink',
      );
    });
  });

  group('typography', () {
    test('stat readouts use tabular, lining figures', () {
      final style = AppTypography.statValue(AppColors.ink);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontFeatures, contains(const FontFeature.liningFigures()));
    });

    test('display slots take the serif and body slots take the sans', () {
      final theme = AppTheme.light();
      expect(theme.textTheme.displayLarge?.fontFamily, AppTypography.displayFamily);
      expect(theme.textTheme.headlineMedium?.fontFamily, AppTypography.displayFamily);
      expect(theme.textTheme.bodyLarge?.fontFamily, AppTypography.textFamily);
      expect(theme.textTheme.bodySmall?.fontFamily, AppTypography.textFamily);
      expect(theme.textTheme.labelSmall?.fontFamily, AppTypography.textFamily);
    });
  });

  test('the trail extension is attached to both themes', () {
    expect(AppTheme.light().trail.trailColors.first, AppColors.amber);
    expect(AppTheme.light().trail.trailColors.last, AppColors.pine);
    expect(AppTheme.dark().trail.trailColors.first, AppColors.amber);
  });
}
