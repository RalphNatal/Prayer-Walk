import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import 'motion.dart';
import 'trail_painter.dart';

/// The app's map surface, and the **only** file that imports `flutter_map`.
///
/// Everything above it speaks in `List<LatLng>` and [TrailWaypoint]. Swapping
/// OSM tiles for Mapbox, MapLibre or a native SDK means rewriting this widget
/// and nothing else — which is the reason it exists rather than screens
/// dropping `FlutterMap` in directly.
///
/// Tiles come from OpenStreetMap over the network. That is the one remote call
/// this phase makes; there is no app backend yet.
class RouteMapView extends StatefulWidget {
  const RouteMapView({
    super.key,
    this.points = const [],
    this.waypoints = const [],
    this.center,
    this.height,
    this.interactive = true,
    this.showAttribution = true,
    this.showEndpoints = true,
    this.strokeWidth = 6,
    this.fitPadding = const EdgeInsets.all(44),
    this.initialZoom = 15.5,
    this.pulsePoint,
    this.followPoint,
    this.overlay,
    this.semanticLabel,
    this.borderRadius,
  });

  /// The traced route. Empty renders the basemap around [center] — which is
  /// what the pre-activity screen wants.
  final List<LatLng> points;
  final List<TrailWaypoint> waypoints;

  /// Used when [points] is empty. Ignored otherwise, since the route decides
  /// the camera.
  final LatLng? center;

  final double? height;
  final bool interactive;
  final bool showAttribution;
  final bool showEndpoints;
  final double strokeWidth;
  final EdgeInsets fitPadding;
  final double initialZoom;

  /// Draws a breathing amber ring here — the live screen's "you are here".
  /// Still under reduced motion.
  final LatLng? pulsePoint;

  /// Keeps the camera on this point as it changes — the live screen following
  /// the walker. [initialCameraFit] only ever runs once, so a growing route
  /// needs this to stay in view. Null (the default) leaves the camera alone.
  final LatLng? followPoint;

  /// Stacked above the map — a recentre button, a scrim, a legend.
  final Widget? overlay;

  /// Read out in place of the map by screen readers, which cannot use tiles.
  final String? semanticLabel;
  final BorderRadius? borderRadius;

  static const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Only reached when a caller passes neither route nor centre.
  static const _fallbackCenter = LatLng(14.5794, 121.0359);

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(RouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final follow = widget.followPoint;
    if (follow == null || follow == oldWidget.followPoint) return;
    // `camera` throws until the map has laid out at least once, and a fix can
    // land in that window. A missed recentre is not worth crashing a recording.
    try {
      _mapController.move(follow, _mapController.camera.zoom);
    } catch (_) {
      /* Map not ready — the next fix will recentre. */
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trail = theme.trail;
    final points = widget.points;
    final waypoints = widget.waypoints;
    final hasRoute = points.length >= 2;
    final interactive = widget.interactive;
    final strokeWidth = widget.strokeWidth;
    final pulsePoint = widget.pulsePoint;
    final overlay = widget.overlay;
    final borderRadius = widget.borderRadius;
    final height = widget.height;
    final semanticLabel = widget.semanticLabel;

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            widget.center ??
            widget.followPoint ??
            (points.isNotEmpty ? points.first : RouteMapView._fallbackCenter),
        initialZoom: widget.initialZoom,
        // Fits the whole route once, on first layout. A live recording passes
        // [followPoint] instead and keeps the camera on the walker.
        initialCameraFit: hasRoute && widget.followPoint == null
            ? CameraFit.coordinates(
                coordinates: points,
                padding: widget.fitPadding,
              )
            : null,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: RouteMapView._osmTiles,
          userAgentPackageName: 'com.calledpresentations.prayer_walk',
          maxNativeZoom: 19,
          tileDisplay: const TileDisplay.fadeIn(
            duration: AppDurations.fast,
          ),
        ),
        if (hasRoute) ...[
          // Casing first, then the gradient trail on top of it, so the line
          // stays readable where it crosses busy tiles.
          PolylineLayer<Object>(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: strokeWidth + 3,
                color: trail.trailUnderlay,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
          PolylineLayer<Object>(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: strokeWidth,
                gradientColors: trail.trailColors,
                colorsStop: trail.trailStops,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        ],
        if (waypoints.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final waypoint in waypoints)
                Marker(
                  point: waypoint.point,
                  width: 34,
                  height: 34,
                  child: _CandleMarker(
                    trail: trail,
                    tint: waypoint.tint,
                    label: waypoint.label,
                  ),
                ),
            ],
          ),
        if (hasRoute && widget.showEndpoints)
          MarkerLayer(
            markers: [
              Marker(
                point: points.first,
                width: 22,
                height: 22,
                child: _EndpointMarker(color: trail.startMark, filled: false),
              ),
              Marker(
                point: points.last,
                width: 22,
                height: 22,
                child: _EndpointMarker(color: trail.endMark, filled: true),
              ),
            ],
          ),
        if (pulsePoint != null)
          MarkerLayer(
            markers: [
              Marker(
                point: pulsePoint,
                width: 72,
                height: 72,
                child: _PulseMarker(color: trail.endMark),
              ),
            ],
          ),
        if (widget.showAttribution)
          SimpleAttributionWidget(
            source: Text(
              'OpenStreetMap contributors',
              style: theme.textTheme.bodySmall,
            ),
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.82),
          ),
      ],
    );

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        map,
        if (overlay != null) IgnorePointer(child: overlay),
      ],
    );

    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius, child: content);
    }
    if (height != null) {
      content = SizedBox(height: height, child: content);
    }

    return Semantics(
      label: semanticLabel ??
          (hasRoute ? 'Map of the traced route' : 'Map of your current area'),
      image: true,
      excludeSemantics: true,
      child: content,
    );
  }
}

/// A prayer waypoint on the map: the same candle the painter draws.
class _CandleMarker extends StatelessWidget {
  const _CandleMarker({required this.trail, required this.label, this.tint});

  final AppTrailTheme trail;
  final Color? tint;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label.isEmpty ? 'Prayer waypoint' : 'Prayer waypoint: $label',
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tint ?? trail.waypointCore,
            border: Border.all(color: trail.trailUnderlay, width: 2),
            boxShadow: [
              BoxShadow(
                color: trail.waypointHalo,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The live screen's "you are here": a candle that breathes.
///
/// Under reduced motion the ring is drawn once, at rest — the position is the
/// information, the breathing is only decoration.
class _PulseMarker extends StatefulWidget {
  const _PulseMarker({required this.color});

  final Color color;

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.value = 0.55;
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
    return Semantics(
      label: 'Current position',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 24 + 44 * t,
                  height: 24 + 44 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.28 * (1 - t)),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EndpointMarker extends StatelessWidget {
  const _EndpointMarker({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Center(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color : surface,
          border: Border.all(color: filled ? surface : color, width: 3),
        ),
      ),
    );
  }
}
