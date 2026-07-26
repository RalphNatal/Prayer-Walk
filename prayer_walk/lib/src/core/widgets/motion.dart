import 'package:flutter/material.dart';

extension MotionX on BuildContext {
  /// True when the platform asks for reduced motion, or when a screen reader /
  /// switch control is driving navigation.
  ///
  /// Every decorative flourish in this app — the live pulse, the trail bloom,
  /// shimmer on skeletons — checks this and renders a still frame instead. The
  /// information is always in the still frame; the motion only ever decorates.
  bool get reduceMotion =>
      MediaQuery.disableAnimationsOf(this) ||
      MediaQuery.accessibleNavigationOf(this);

  /// Text scale, clamped so the layout survives the largest accessibility
  /// sizes on dense surfaces (stat rows, nav labels).
  double clampedTextScale({double max = 1.6}) =>
      MediaQuery.textScalerOf(this).scale(1).clamp(1.0, max);
}
