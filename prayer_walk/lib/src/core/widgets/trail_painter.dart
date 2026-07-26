import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// latlong2 exports its own `Path`, which would shadow the one we paint with.
import 'package:latlong2/latlong.dart' hide Path;

import '../theme/app_theme.dart';

/// A prayer waypoint, as the trail renderers want it.
///
/// Deliberately not the domain `Waypoint`: core widgets do not import feature
/// code. Feature screens map into this with `.toTrailWaypoints()`.
class TrailWaypoint {
  const TrailWaypoint({required this.point, this.label = '', this.tint});

  final LatLng point;
  final String label;

  /// Overrides the candle colour. Null uses the theme's waypoint core.
  final Color? tint;
}

/// Flattens lat/lng onto a canvas rect.
///
/// An equirectangular projection with a cos(latitude) correction on x. Over the
/// few kilometres a route spans it is indistinguishable from Mercator, and it
/// keeps the painted trail's shape honest against the same route drawn on the
/// real map.
class TrailProjection {
  TrailProjection._(this._originX, this._originY, this._scale, this._offset, this._lngScale);

  final double _originX;
  final double _originY;
  final double _scale;
  final Offset _offset;
  final double _lngScale;

  factory TrailProjection.fit(
    List<LatLng> points,
    Size size, {
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    final midLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final lngScale = math.cos(midLat * math.pi / 180).abs().clamp(0.01, 1.0);

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in points) {
      final x = p.longitude * lngScale;
      final y = -p.latitude;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }

    final available = Size(
      math.max(size.width - padding.horizontal, 1),
      math.max(size.height - padding.vertical, 1),
    );
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    final scale = math.min(available.width / spanX, available.height / spanY);

    // Centre whatever is left over after the uniform fit.
    final drawnWidth = spanX * scale;
    final drawnHeight = spanY * scale;
    final offset = Offset(
      padding.left + (available.width - drawnWidth) / 2,
      padding.top + (available.height - drawnHeight) / 2,
    );

    return TrailProjection._(minX, minY, scale, offset, lngScale);
  }

  Offset project(LatLng p) => Offset(
    (p.longitude * _lngScale - _originX) * _scale + _offset.dx,
    (-p.latitude - _originY) * _scale + _offset.dy,
  );
}

/// Paints the signature trail: a lit amber-to-pine line with candle waypoints.
///
/// Shared by the card hero and any other tile-less surface. The map layer draws
/// the same colours through `flutter_map`'s polyline, so a route looks like one
/// object whether or not it is sitting on tiles.
class TrailPainter extends CustomPainter {
  const TrailPainter({
    required this.points,
    required this.trail,
    this.waypoints = const [],
    this.strokeWidth = 4.5,
    this.showGround = true,
    this.showGlow = true,
    this.showEndpoints = true,
    this.padding = const EdgeInsets.all(18),
  });

  final List<LatLng> points;
  final List<TrailWaypoint> waypoints;
  final AppTrailTheme trail;
  final double strokeWidth;

  /// Paints the tinted ground and contour texture behind the line.
  final bool showGround;

  /// The bloom under the stroke. Off on very small previews, where it muddies.
  final bool showGlow;
  final bool showEndpoints;
  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (showGround) _paintGround(canvas, rect);
    if (points.length < 2) return;

    final projection = TrailProjection.fit(points, size, padding: padding);
    final projected = points.map(projection.project).toList(growable: false);

    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (var i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }

    if (showGlow) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = trail.trailGlow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 1.6),
      );
    }

    // A darker casing keeps the line legible where it crosses itself.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = trail.trailUnderlay,
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = _trailShader(projected),
    );

    for (final waypoint in waypoints) {
      _paintCandle(
        canvas,
        projection.project(waypoint.point),
        waypoint.tint ?? trail.waypointCore,
      );
    }

    if (showEndpoints) {
      _paintEndpoint(canvas, projected.first, trail.startMark, filled: false);
      _paintEndpoint(canvas, projected.last, trail.endMark, filled: true);
    }
  }

  /// Runs the gradient along the direction of travel where there is one, and
  /// across the diagonal for loops that finish where they started.
  ui.Shader _trailShader(List<Offset> projected) {
    final start = projected.first;
    final end = projected.last;
    final bounds = _boundsOf(projected);
    final diagonal = bounds.bottomRight - bounds.topLeft;
    final travelled = (end - start).distance;

    final (from, to) = travelled > diagonal.distance * 0.2
        ? (start, end)
        : (bounds.topLeft, bounds.bottomRight);

    return ui.Gradient.linear(from, to, trail.trailColors, trail.trailStops);
  }

  Rect _boundsOf(List<Offset> projected) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final o in projected) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _paintGround(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          trail.groundTop,
          trail.groundBottom,
        ]),
    );

    // Faint contour texture, so the ground is not a flat swatch.
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = trail.contour;
    for (var i = 1; i <= 4; i++) {
      final y = rect.height * i / 5;
      final path = Path()..moveTo(rect.left - 10, y);
      for (var x = 0.0; x <= rect.width + 20; x += 28) {
        path.relativeQuadraticBezierTo(
          14,
          i.isEven ? -6 : 6,
          28,
          math.sin(i * 1.7) * 3,
        );
      }
      canvas.drawPath(path, contour);
    }
  }

  /// A candle: warm halo, dark rim so it holds on light tiles, bright core.
  void _paintCandle(Canvas canvas, Offset center, Color core) {
    canvas.drawCircle(
      center,
      strokeWidth * 2.4,
      Paint()
        ..color = trail.waypointHalo
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth),
    );
    canvas.drawCircle(
      center,
      strokeWidth * 1.15,
      Paint()..color = trail.trailUnderlay,
    );
    canvas.drawCircle(center, strokeWidth * 0.85, Paint()..color = core);
  }

  void _paintEndpoint(
    Canvas canvas,
    Offset center,
    Color color, {
    required bool filled,
  }) {
    canvas.drawCircle(
      center,
      strokeWidth * 1.5,
      Paint()..color = trail.groundTop.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      center,
      strokeWidth * 1.15,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(TrailPainter old) =>
      old.points != points ||
      old.waypoints != waypoints ||
      old.trail != trail ||
      old.strokeWidth != strokeWidth ||
      old.showGround != showGround;
}
