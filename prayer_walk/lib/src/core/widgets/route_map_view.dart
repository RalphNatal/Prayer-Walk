import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/app_logger.dart';
import 'motion.dart';
import 'trail_painter.dart';

/// The app's map surface, and the **only** file that imports `flutter_map`.
///
/// Everything above it speaks in `List<LatLng>` and [TrailWaypoint]. Swapping
/// OSM tiles for Mapbox, MapLibre or a native SDK means rewriting this widget
/// and nothing else — which is the reason it exists rather than screens
/// dropping `FlutterMap` in directly.
///
/// Tiles come from Mapbox, keyed by `MAPBOX_ACCESS_TOKEN` in `env.json`. The
/// tile provider has nothing to do with positioning accuracy — that is entirely
/// the location service's job — but it does decide whether a *correct* position
/// lands on a well-drawn basemap or on sparse, misaligned data, which in parts
/// of the world is the difference between a map that looks right and one that
/// looks broken. It also comes with a licence that permits app traffic, which
/// the public OSM tile server does not.
class RouteMapView extends StatefulWidget {
  const RouteMapView({
    super.key,
    this.points = const [],
    this.waypoints = const [],
    this.center,
    this.height,
    this.interactive = true,
    this.showEndpoints = true,
    this.strokeWidth = 6,
    this.fitPadding = const EdgeInsets.all(44),
    this.initialZoom = 15.5,
    this.pulsePoint,
    this.accuracyMeters,
    this.followPoint,
    this.overlay,
    this.semanticLabel,
    this.borderRadius,
    this.locatingLabel = 'Finding you…',
    this.revealProgress = 1,
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
  final bool showEndpoints;
  final double strokeWidth;
  final EdgeInsets fitPadding;
  final double initialZoom;

  /// Draws a breathing amber ring here — the live screen's "you are here".
  /// Still under reduced motion.
  final LatLng? pulsePoint;

  /// The accuracy radius of [pulsePoint], drawn to scale as a translucent
  /// circle. This is the affordance that turns "the app is wrong" into "my GPS
  /// hasn't locked yet" — a dot claims a point, a circle claims an area, and
  /// the circle is the truthful claim. Null draws no circle.
  final double? accuracyMeters;

  /// Keeps the camera on this point as it changes — the live screen following
  /// the walker. [initialCameraFit] only ever runs once, so a growing route
  /// needs this to stay in view. Null (the default) leaves the camera alone.
  final LatLng? followPoint;

  /// Stacked above the map — a recentre button, a scrim, a legend.
  final Widget? overlay;

  /// Read out in place of the map by screen readers, which cannot use tiles.
  final String? semanticLabel;
  final BorderRadius? borderRadius;

  /// Shown instead of the map when there is no route, no centre and no
  /// position — see [_LocatingView].
  final String locatingLabel;

  /// How much of [points] to draw, 0 to 1. Defaults to the whole route, which
  /// is what every caller but one wants.
  ///
  /// The summary screen animates this from zero so the walk that was just
  /// finished draws itself in rather than arriving fully formed. Only the line
  /// is affected: the camera still fits the *complete* route on first layout,
  /// so the map does not creep outwards as the trail grows, and the end marker
  /// waits until there is an end to mark.
  ///
  /// Nothing about tiles, accuracy or the live camera reads this. A caller that
  /// leaves it alone gets exactly the previous behaviour.
  final double revealProgress;

  /// Fallback only. The public OSM tile server is community-funded and its
  /// usage policy does not permit production app traffic — a release build
  /// without a token is a licensing problem, not just a cosmetic one, which is
  /// why [_MapTiles] logs a warning when it lands here.
  static const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Where the camera goes, or null when nothing has earned the right to say.
  ///
  /// There is deliberately no fallback. This used to end in a hardcoded centre
  /// copied out of the mock seed, which meant a caller with no route and no fix
  /// silently showed every user in the world standing in one Metro Manila
  /// suburb, indistinguishable from a real position. A map that does not know
  /// where you are must say so.
  LatLng? get _camera =>
      center ?? followPoint ?? (points.isNotEmpty ? points.first : null);

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

    // The portion of the route the line shows. At the default progress of 1
    // this is the same list object, so the ordinary case allocates nothing.
    // Always at least two points once there is a route, so a reveal starting
    // from zero begins as a short stroke rather than a flicker of nothing.
    final reveal = widget.revealProgress.clamp(0.0, 1.0);
    final drawn = !hasRoute || reveal >= 1
        ? points
        : points.take(
            (points.length * reveal).round().clamp(2, points.length),
          ).toList(growable: false);
    final fullyDrawn = drawn.length == points.length;
    final interactive = widget.interactive;
    final strokeWidth = widget.strokeWidth;
    final pulsePoint = widget.pulsePoint;
    final overlay = widget.overlay;
    final borderRadius = widget.borderRadius;
    final height = widget.height;
    final semanticLabel = widget.semanticLabel;
    final camera = widget._camera;
    final tiles = _MapTiles.resolve(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );

    // Nothing to centre on. Rather than invent a position, say plainly that we
    // are still looking — the one state the old fallback centre made
    // unreachable, and the honest answer everywhere outside Metro Manila.
    if (camera == null) {
      return _LocatingView(
        label: widget.locatingLabel,
        height: height,
        borderRadius: borderRadius,
        overlay: overlay,
      );
    }

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: camera,
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
          urlTemplate: tiles.urlTemplate,
          additionalOptions: tiles.additionalOptions,
          userAgentPackageName: 'com.calledpresentations.prayer_walk',
          maxNativeZoom: tiles.maxNativeZoom,
          retinaMode: tiles.retina,
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
                points: drawn,
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
                points: drawn,
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
              // The end mark waits for the line to reach it. Sitting at the
              // finish while the trail is still halfway there would give away
              // the ending of the one animation in the app that has one.
              if (fullyDrawn)
                Marker(
                  point: points.last,
                  width: 22,
                  height: 22,
                  child: _EndpointMarker(color: trail.endMark, filled: true),
                ),
            ],
          ),
        // The accuracy circle goes under the marker, so the dot still reads as
        // the position and the circle as the uncertainty around it.
        if (pulsePoint != null && (widget.accuracyMeters ?? 0) > 0)
          CircleLayer<Object>(
            circles: [
              CircleMarker(
                point: pulsePoint,
                radius: widget.accuracyMeters!,
                // Metres, not pixels — the circle has to grow and shrink with
                // the zoom or it is decoration rather than information.
                useRadiusInMeter: true,
                color: trail.endMark.withValues(alpha: 0.12),
                borderColor: trail.endMark.withValues(alpha: 0.35),
                borderStrokeWidth: 1,
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
        // Unconditional, and deliberately not behind a flag. Credit is a
        // condition of the tile licence — Mapbox's and OpenStreetMap's alike —
        // and a `showAttribution: false` parameter is an invitation to breach
        // it on whichever screen feels too cramped that week.
        SimpleAttributionWidget(
          source: Text(tiles.attribution, style: theme.textTheme.bodySmall),
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

/// Which basemap the app is drawing on, and what it is obliged to say about it.
///
/// Every Mapbox-specific string lives in this class and nowhere else. Screens
/// pass routes and points; they have never heard of a style id or a token, so
/// changing provider is a change to this one type.
///
/// Attribution is not optional decoration. Mapbox, OpenStreetMap and every
/// other provider require visible credit as a condition of the licence, which
/// is why [attribution] has no null case.
class _MapTiles {
  const _MapTiles._({
    required this.urlTemplate,
    required this.attribution,
    required this.retina,
    this.additionalOptions = const {},
  });

  /// Reads the configured provider, falling back to OSM when there is no token.
  ///
  /// [devicePixelRatio] decides the retina variant: serving `@2x` tiles to a
  /// 1x display wastes bandwidth, and serving 1x tiles to a modern phone looks
  /// blurry — and a blurry basemap gets read as an inaccurate one.
  factory _MapTiles.resolve({required double devicePixelRatio}) {
    final retina = devicePixelRatio > 1.5;

    if (!AppConfig.hasMapboxToken) {
      // Debug builds keep working unconfigured; release builds should not be
      // here at all, so say so loudly enough to be caught before shipping —
      // but once, not on every rebuild of every map.
      if (!_warnedAboutMissingToken) {
        _warnedAboutMissingToken = true;
        AppLogger.warn(
          'PW-MAP',
          'MAPBOX_ACCESS_TOKEN is empty — falling back to public OSM tiles, '
          'which are not licensed for app traffic. Set it in env.json.',
        );
      }
      return _MapTiles._(
        urlTemplate: RouteMapView._osmTiles,
        attribution: '© OpenStreetMap contributors',
        // The OSM tile server has no @2x variant; asking for one 404s.
        retina: false,
      );
    }

    return _MapTiles._(
      // `{r}` is flutter_map's retina placeholder — it expands to `@2x` or to
      // nothing, driven by `retinaMode` on the layer.
      urlTemplate:
          'https://api.mapbox.com/styles/v1/{style}/tiles/512/{z}/{x}/{y}{r}'
          '?access_token={accessToken}',
      attribution: '© Mapbox © OpenStreetMap',
      retina: retina,
      additionalOptions: {
        'style': _mapboxStyle,
        'accessToken': AppConfig.mapboxAccessToken,
      },
    );
  }

  /// Mapbox Outdoors: trails, paths and contours are drawn, which is the right
  /// emphasis for an app about walking.
  static const _mapboxStyle = 'mapbox/outdoors-v12';

  static bool _warnedAboutMissingToken = false;

  final String urlTemplate;
  final String attribution;
  final bool retina;
  final Map<String, String> additionalOptions;

  /// 512 px Mapbox tiles cover two standard zoom levels each, so the highest
  /// native level is one below OSM's.
  int get maxNativeZoom => AppConfig.hasMapboxToken ? 18 : 19;
}

/// What the map shows when it does not know where the person is.
///
/// The whole point of this widget is that it is visually *unlike* a map with a
/// position on it. The bug it replaces was not that the old fallback centre was
/// the wrong city — it was that a guess and a fix looked identical, so there
/// was nothing on screen to distrust.
class _LocatingView extends StatelessWidget {
  const _LocatingView({
    required this.label,
    this.height,
    this.borderRadius,
    this.overlay,
  });

  final String label;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trail = theme.trail;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [trail.groundTop, trail.groundBottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 28,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (overlay != null) IgnorePointer(child: overlay!),
        ],
      ),
    );

    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    if (height != null) {
      content = SizedBox(height: height, child: content);
    }

    return Semantics(label: label, child: content);
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
