import 'package:flutter/widgets.dart';

/// Spacing scale. Every gap in the app comes from here so rhythm stays even.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal gutter for scrollable screen content.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);

  /// Padding for list bodies that end above a bottom navigation bar.
  static const EdgeInsets listBody = EdgeInsets.fromLTRB(lg, lg, lg, xxxl * 2);
}

/// Corner radii. Cards and sheets are generously rounded; controls less so.
abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius control = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Motion durations. All flourishes are additionally gated on reduced motion.
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 480);
  static const Duration pulse = Duration(milliseconds: 1800);
  static const Duration splash = Duration(milliseconds: 1300);
}

/// Layout breakpoints. The admin rail/drawer switch keys off [wide].
abstract final class AppBreakpoints {
  static const double compact = 480;
  static const double medium = 700;
  static const double wide = 900;
  static const double extraWide = 1240;
}

/// Minimum interactive size, per platform accessibility guidance.
abstract final class AppSizes {
  static const double minTapTarget = 48;
  static const double avatarSm = 32;
  static const double avatarMd = 44;
  static const double avatarLg = 72;
  static const double cardTrailHeight = 176;
}
