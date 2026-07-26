import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';

/// The brand mark: a trail kindling as it climbs.
///
/// The same amber-to-pine language as a recorded route, abstracted — so the
/// first thing a person sees on the splash is the thing every card will show
/// them later. Painted rather than traced from fixture data, because this is
/// artwork, not a walk anyone took.
class BrandTrailMark extends StatefulWidget {
  const BrandTrailMark({super.key, this.size = 168, this.animate = true});

  final double size;

  /// Draws the trail on, once. Ignored under reduced motion, where the mark
  /// simply appears complete.
  final bool animate;

  @override
  State<BrandTrailMark> createState() => _BrandTrailMarkState();
}

class _BrandTrailMarkState extends State<BrandTrailMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !context.reduceMotion) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trail = Theme.of(context).trail;
    return Semantics(
      label: 'Prayer Walk',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.72,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) => CustomPaint(
            painter: _BrandTrailPainter(trail: trail, progress: _progress.value),
          ),
        ),
      ),
    );
  }
}

class _BrandTrailPainter extends CustomPainter {
  const _BrandTrailPainter({required this.trail, required this.progress});

  final AppTrailTheme trail;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.06, h * 0.92)
      ..cubicTo(w * 0.30, h * 0.86, w * 0.18, h * 0.46, w * 0.46, h * 0.44)
      ..cubicTo(w * 0.74, h * 0.42, w * 0.62, h * 0.16, w * 0.94, h * 0.08);

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress.clamp(0, 1));

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = trail.trailGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: trail.trailColors.reversed.toList(),
          stops: trail.trailStops,
        ).createShader(Offset.zero & size),
    );

    // Three candles along the way.
    for (final at in const [0.22, 0.55, 0.88]) {
      if (progress < at) continue;
      final position = metric.getTangentForOffset(metric.length * at)?.position;
      if (position == null) continue;
      canvas.drawCircle(
        position,
        11,
        Paint()
          ..color = trail.waypointHalo
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(position, 4.5, Paint()..color = trail.waypointCore);
    }
  }

  @override
  bool shouldRepaint(_BrandTrailPainter old) =>
      old.progress != progress || old.trail != trail;
}
