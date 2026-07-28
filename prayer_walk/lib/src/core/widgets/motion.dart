import 'dart:math' as math;

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

/// How long the app's transitions and responses take.
///
/// Collected so the vocabulary is visible in one place rather than inferred
/// from a dozen literals. Nothing here is longer than a third of a second: this
/// is an app someone opens mid-walk, and a considered pace is not a slow one.
abstract final class AppMotion {
  /// Peer-to-peer moves — switching a tab. Short enough to feel like the same
  /// screen changing rather than a journey.
  static const Duration quick = Duration(milliseconds: 180);

  /// Pushing into or out of a detail screen.
  static const Duration standard = Duration(milliseconds: 240);

  /// The record → live → summary progression, which is one act and gets the
  /// longest of the three.
  static const Duration deliberate = Duration(milliseconds: 300);

  /// Calm easing, nothing overshooting. There is no spring in this app on
  /// purpose — a bounce reads as celebration, and nothing here is celebrating.
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// A brief kindling when [lit] turns true: the child swells a few percent and
/// settles.
///
/// Used on the encouragement control, where the amber coming on should feel
/// like a light being lit rather than a checkbox being ticked. It is a few
/// percent and a quarter of a second — if it reads as an animation rather than
/// as the button responding, it is too much.
///
/// Renders a still frame under reduced motion: the lit state is carried
/// entirely by colour and label, and this only ever decorates it.
class Kindle extends StatefulWidget {
  const Kindle({super.key, required this.lit, required this.child});

  final bool lit;
  final Widget child;

  @override
  State<Kindle> createState() => _KindleState();
}

class _KindleState extends State<Kindle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void didUpdateWidget(Kindle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rising edge only. Withdrawing an encouragement is a correction, and a
    // correction should not be given the same flourish as the act.
    if (widget.lit && !oldWidget.lit && !context.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      // The child is built once and reused — the animation only transforms it.
      child: widget.child,
      builder: (context, child) {
        // Out and back: sin over half a period peaks at the midpoint and
        // returns to exactly 1, so the control never settles at a wrong size.
        final t = Curves.easeOut.transform(_controller.value);
        final swell = math.sin(t * math.pi);
        return Transform.scale(scale: 1 + 0.055 * swell, child: child);
      },
    );
  }
}
