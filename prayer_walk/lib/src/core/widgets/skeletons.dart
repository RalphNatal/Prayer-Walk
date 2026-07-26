import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import 'motion.dart';

/// Drives every skeleton beneath it from one ticker.
///
/// Loading screens can show a dozen placeholder blocks; giving each its own
/// [AnimationController] would spin up a dozen tickers for one effect. The
/// sweep is also skipped entirely under reduced motion, where the skeletons
/// render as flat blocks — they still say "content is coming", just without
/// the movement.
class ShimmerScope extends StatefulWidget {
  const ShimmerScope({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerTicker(animation: _controller, child: widget.child);
  }
}

class _ShimmerTicker extends InheritedWidget {
  const _ShimmerTicker({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ShimmerTicker>()
      ?.animation;

  @override
  bool updateShouldNotify(_ShimmerTicker oldWidget) =>
      oldWidget.animation != animation;
}

/// A placeholder block sized like the content it stands in for.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.xs,
  });

  const SkeletonBox.line({super.key, this.width, this.height = 12})
    : radius = AppRadius.xs;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.07);
    final highlight = scheme.onSurface.withValues(alpha: 0.13);
    final animation = context.reduceMotion ? null : _ShimmerTicker.maybeOf(context);

    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (animation == null) return box;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.6 + t * 3.2, 0),
            end: Alignment(-0.6 + t * 3.2, 0),
            colors: [base, highlight, base],
          ).createShader(rect),
          child: child,
        );
      },
      child: box,
    );
  }
}

/// A pilgrimage card's silhouette: trail hero, byline, caption.
class PilgrimageCardSkeleton extends StatelessWidget {
  const PilgrimageCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: AppSizes.cardTrailHeight, radius: 0),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    SkeletonBox(width: 36, height: 36, radius: AppRadius.pill),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox.line(width: 140),
                          SizedBox(height: AppSpacing.sm),
                          SkeletonBox.line(width: 90, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const SkeletonBox.line(width: 220),
                const SizedBox(height: AppSpacing.sm),
                const SkeletonBox.line(width: 160, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A generic list row: leading circle, two lines of text.
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key, this.leadingSize = 40});

  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          SkeletonBox(
            width: leadingSize,
            height: leadingSize,
            radius: AppRadius.pill,
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox.line(width: 180),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox.line(width: 110, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading view for card feeds.
class CardListLoading extends StatelessWidget {
  const CardListLoading({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.lg),
            const PilgrimageCardSkeleton(),
          ],
        ],
      ),
    );
  }
}

/// Loading view for plain lists and tables.
class RowListLoading extends StatelessWidget {
  const RowListLoading({super.key, this.count = 5, this.leadingSize = 40});

  final int count;
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ListRowSkeleton(leadingSize: leadingSize),
        ],
      ),
    );
  }
}
