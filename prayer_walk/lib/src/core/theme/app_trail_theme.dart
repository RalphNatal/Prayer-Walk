import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The signature element, themed.
///
/// A recorded route is drawn as light kindled along the ground: an amber head
/// falling back through moss into pine. Prayer waypoints sit on that line as
/// small candle dots with a warm halo. Every surface that draws a trail — the
/// map layer and the painted card hero alike — reads its colours from here, so
/// the trail looks like one object across the app.
@immutable
class AppTrailTheme extends ThemeExtension<AppTrailTheme> {
  const AppTrailTheme({
    required this.trailColors,
    required this.trailStops,
    required this.trailGlow,
    required this.trailUnderlay,
    required this.waypointCore,
    required this.waypointHalo,
    required this.startMark,
    required this.endMark,
    required this.groundTop,
    required this.groundBottom,
    required this.contour,
  });

  /// Stops of the amber -> moss -> pine gradient, in draw order.
  final List<Color> trailColors;
  final List<double> trailStops;

  /// Soft bloom painted beneath the stroke so the line reads as *lit*.
  final Color trailGlow;

  /// Darker casing under the stroke, which keeps the line legible over busy
  /// map tiles without turning it into a flat highway.
  final Color trailUnderlay;

  final Color waypointCore;
  final Color waypointHalo;
  final Color startMark;
  final Color endMark;

  /// Ground the painted (tile-less) trail preview sits on.
  final Color groundTop;
  final Color groundBottom;
  final Color contour;

  static const AppTrailTheme light = AppTrailTheme(
    trailColors: [AppColors.amber, Color(0xFFB98341), AppColors.moss, AppColors.pine],
    trailStops: [0.0, 0.32, 0.68, 1.0],
    trailGlow: Color(0x66E3A24A),
    trailUnderlay: Color(0x33223D30),
    waypointCore: Color(0xFFFFE2B0),
    waypointHalo: Color(0x99E3A24A),
    startMark: AppColors.pine,
    endMark: AppColors.amber,
    groundTop: Color(0xFFF7F2E8),
    groundBottom: Color(0xFFE2DBCA),
    contour: Color(0x33223D30),
  );

  static const AppTrailTheme dark = AppTrailTheme(
    trailColors: [AppColors.amber, Color(0xFFC98F45), AppColors.mossLight, Color(0xFF2F5540)],
    trailStops: [0.0, 0.32, 0.68, 1.0],
    trailGlow: Color(0x7AE3A24A),
    trailUnderlay: Color(0x5C000000),
    waypointCore: Color(0xFFFFEACA),
    waypointHalo: Color(0xB3E3A24A),
    startMark: AppColors.mossLight,
    endMark: AppColors.amber,
    groundTop: Color(0xFF20342A),
    groundBottom: Color(0xFF13221B),
    contour: Color(0x3D6FA57F),
  );

  @override
  AppTrailTheme copyWith({
    List<Color>? trailColors,
    List<double>? trailStops,
    Color? trailGlow,
    Color? trailUnderlay,
    Color? waypointCore,
    Color? waypointHalo,
    Color? startMark,
    Color? endMark,
    Color? groundTop,
    Color? groundBottom,
    Color? contour,
  }) {
    return AppTrailTheme(
      trailColors: trailColors ?? this.trailColors,
      trailStops: trailStops ?? this.trailStops,
      trailGlow: trailGlow ?? this.trailGlow,
      trailUnderlay: trailUnderlay ?? this.trailUnderlay,
      waypointCore: waypointCore ?? this.waypointCore,
      waypointHalo: waypointHalo ?? this.waypointHalo,
      startMark: startMark ?? this.startMark,
      endMark: endMark ?? this.endMark,
      groundTop: groundTop ?? this.groundTop,
      groundBottom: groundBottom ?? this.groundBottom,
      contour: contour ?? this.contour,
    );
  }

  @override
  AppTrailTheme lerp(covariant AppTrailTheme? other, double t) {
    if (other == null) return this;
    return AppTrailTheme(
      trailColors: [
        for (var i = 0; i < trailColors.length; i++)
          Color.lerp(trailColors[i], other.trailColors[i], t)!,
      ],
      trailStops: [
        for (var i = 0; i < trailStops.length; i++)
          trailStops[i] + (other.trailStops[i] - trailStops[i]) * t,
      ],
      trailGlow: Color.lerp(trailGlow, other.trailGlow, t)!,
      trailUnderlay: Color.lerp(trailUnderlay, other.trailUnderlay, t)!,
      waypointCore: Color.lerp(waypointCore, other.waypointCore, t)!,
      waypointHalo: Color.lerp(waypointHalo, other.waypointHalo, t)!,
      startMark: Color.lerp(startMark, other.startMark, t)!,
      endMark: Color.lerp(endMark, other.endMark, t)!,
      groundTop: Color.lerp(groundTop, other.groundTop, t)!,
      groundBottom: Color.lerp(groundBottom, other.groundBottom, t)!,
      contour: Color.lerp(contour, other.contour, t)!,
    );
  }
}

extension AppTrailThemeX on ThemeData {
  /// Never null in this app; falls back to the light trail defensively so a
  /// bare `ThemeData()` in a test or preview still paints something sane.
  AppTrailTheme get trail => extension<AppTrailTheme>() ?? AppTrailTheme.light;
}
