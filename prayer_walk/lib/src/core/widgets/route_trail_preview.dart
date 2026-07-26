import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'trail_painter.dart';

/// The trail without a basemap — the hero of every pilgrimage card.
///
/// Feed and history lead with the *shape of the walk*, not a grid of numbers,
/// and they scroll. Painting the route rather than mounting a live map per card
/// keeps that scroll cheap (no tile requests, no map controllers) and puts the
/// gradient trail on a ground we control. Screens that need a real basemap —
/// detail, record, live, summary — use [RouteMapView] instead.
class RouteTrailPreview extends StatelessWidget {
  const RouteTrailPreview({
    super.key,
    required this.points,
    this.waypoints = const [],
    this.height = AppSizes.cardTrailHeight,
    this.strokeWidth = 4.5,
    this.showGround = true,
    this.showGlow = true,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
    this.emptyLabel = 'No route traced',
  });

  final List<LatLng> points;
  final List<TrailWaypoint> waypoints;
  final double height;
  final double strokeWidth;
  final bool showGround;
  final bool showGlow;
  final EdgeInsets padding;
  final String? semanticLabel;

  /// Shown when there is no route — logging an activity without one is valid.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trail = theme.trail;

    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [trail.groundTop, trail.groundBottom],
            ),
          ),
          child: Center(
            child: Text(
              emptyLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel ?? 'Traced route',
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: TrailPainter(
              points: points,
              waypoints: waypoints,
              trail: trail,
              strokeWidth: strokeWidth,
              showGround: showGround,
              showGlow: showGlow,
              padding: padding,
            ),
          ),
        ),
      ),
    );
  }
}
