import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/motion.dart';

/// The app's transition vocabulary. Three moves, and no others.
///
/// Stock Material slides every pushed route in from the right, which reads as
/// travel. Most of what this app pushes is not travel — opening a walk you are
/// already looking at, or a devotional off the shelf — so those get a
/// fade-through instead, and the horizontal move is reserved for the one place
/// there genuinely is a forward direction: record → live → summary.
///
/// Every one of these collapses to an instant cut under reduced motion. That is
/// decided here, once, by handing the page a zero duration — not by each
/// builder remembering to check.
///
/// Durations live in [AppMotion] beside the rest of the app's timing.

/// Opening something you are already looking at: a walk, a profile, a
/// devotional, a settings screen.
///
/// Fade-through with a two-percent lift. The scale is small enough that it
/// reads as the page settling rather than zooming; take it out and the fade
/// alone feels flat.
CustomTransitionPage<T> fadeThroughPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final still = context.reduceMotion;
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: still ? Duration.zero : AppMotion.standard,
    reverseTransitionDuration: still ? Duration.zero : AppMotion.quick,
    transitionsBuilder: (context, animation, secondary, child) {
      if (still) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.enter,
        reverseCurve: AppMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// One act, moving forward: record → live → summary.
///
/// A short horizontal move with the fade, so the three screens read as stages
/// of the same thing rather than three separate destinations. This is the only
/// place in the app where a transition carries direction, which is what keeps
/// the direction meaningful.
CustomTransitionPage<T> forwardPage<T>(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final still = context.reduceMotion;
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: still ? Duration.zero : AppMotion.deliberate,
    reverseTransitionDuration: still ? Duration.zero : AppMotion.standard,
    transitionsBuilder: (context, animation, secondary, child) {
      if (still) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.enter,
        reverseCurve: AppMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          // An eighth of the screen, not a full width. The point is a sense of
          // travel, not a journey the walker has to sit through.
          position: Tween<Offset>(
            begin: const Offset(0.12, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Peer destinations inside a shell — the bottom bar, the admin rail.
///
/// A `StatefulShellRoute.indexedStack` swaps branches with no transition at
/// all, which is right in one respect (peers must not slide past each other)
/// and abrupt in another. This fades the incoming branch up.
///
/// It is a fade *in*, not a crossfade, and that is not a compromise — it is the
/// only correct shape here. A crossfade has to hold both branches in the tree
/// at once, and `StatefulNavigationShell` carries the branch navigators'
/// `GlobalKey`s: two of it in the tree is the same key twice, which the
/// framework rejects outright. So there is one instance, always, and the
/// opacity of that one instance is what moves. The indexed stack underneath is
/// untouched — every branch keeps its navigator and scroll position.
class BranchFade extends StatefulWidget {
  const BranchFade({super.key, required this.index, required this.child});

  /// The branch now showing. A change to this is what drives the fade.
  final int index;

  final Widget child;

  @override
  State<BranchFade> createState() => _BranchFadeState();
}

class _BranchFadeState extends State<BranchFade>
    with SingleTickerProviderStateMixin {
  // Starts settled: the first branch is already on screen and has nothing to
  // fade in from.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
    value: 1,
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );

  @override
  void didUpdateWidget(BranchFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !context.reduceMotion) {
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
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}
