import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/privacy_zone.dart';

/// Placing a zone on a map.
///
/// The crosshair does not move; the map moves underneath it. That is the
/// interaction that works one-handed on a phone and, more to the point, the one
/// that never needs a coordinate on screen — the person drags their street into
/// the middle of the circle and presses save. This app displays no latitude and
/// no longitude anywhere, and this screen is the place where that restraint
/// most obviously earns its keep.
///
/// Pops a [PrivacyZoneDraft] on save, or null. Nothing is written from here;
/// the list screen owns the write and the failure copy that goes with it.
class ZoneEditorScreen extends StatefulWidget {
  const ZoneEditorScreen({super.key, this.initial, this.fallbackCentre});

  /// Null when creating.
  final PrivacyZoneDraft? initial;

  /// Where the map opens for a new zone — the device's current position, if it
  /// had one. Null is ordinary: the map says it is still looking rather than
  /// dropping the person somewhere plausible and letting them save it.
  final LatLng? fallbackCentre;

  @override
  State<ZoneEditorScreen> createState() => _ZoneEditorScreenState();
}

class _ZoneEditorScreenState extends State<ZoneEditorScreen> {
  late final TextEditingController _label = TextEditingController(
    text: widget.initial?.label ?? 'Home',
  );

  late LatLng? _centre = widget.initial?.centre ?? widget.fallbackCentre;
  late double _radius =
      (widget.initial?.radiusMeters ?? PrivacyZone.defaultRadiusMeters)
          .toDouble();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final centre = _centre;
    if (centre == null) return;
    Navigator.of(context).pop(
      PrivacyZoneDraft(
        id: widget.initial?.id,
        label: _label.text.trim().isEmpty ? 'Home' : _label.text.trim(),
        centre: centre,
        radiusMeters: _radius.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centre = _centre;
    final creating = widget.initial?.id == null;

    return Scaffold(
      appBar: AppBar(title: Text(creating ? 'New zone' : 'Edit zone')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          SizedBox(
            height: 300,
            child: RouteMapView(
              center: centre,
              height: 300,
              // The circle is drawn to scale in metres by the same layer the
              // recorder uses for a GPS accuracy radius. Both are "an area,
              // not a point", which is exactly what a zone is.
              pulsePoint: centre,
              accuracyMeters: _radius,
              locatingLabel:
                  'Finding you, so the map can open on your street…',
              onCentreChanged: (point) {
                // setState on every frame of a drag is what a map picker is; the
                // only thing rebuilding is the circle and one line of copy.
                if (mounted) setState(() => _centre = point);
              },
              overlay: const _Crosshair(),
              semanticLabel:
                  'Map for placing a privacy zone. Drag the map to move the '
                  'centre of the zone.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  centre == null
                      ? 'Waiting for a position. You can also search the map by '
                            'dragging once it appears.'
                      : 'Drag the map so the crosshair sits over the place you '
                            'want hidden.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),

                TextField(
                  controller: _label,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Home',
                    helperText: 'Only you ever see this.',
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                Row(
                  children: [
                    Expanded(
                      child: Text('Radius', style: theme.textTheme.titleSmall),
                    ),
                    Text(
                      Fmt.distance(_radius),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                Slider(
                  value: _radius,
                  min: PrivacyZone.minRadiusMeters.toDouble(),
                  max: PrivacyZone.maxRadiusMeters.toDouble(),
                  divisions:
                      (PrivacyZone.maxRadiusMeters -
                          PrivacyZone.minRadiusMeters) ~/
                      25,
                  label: Fmt.distance(_radius),
                  onChanged: (value) => setState(() => _radius = value),
                ),
                Text(
                  'Around 200 m covers a street and the corner at either end '
                  'of it. Larger hides more, and shortens more of every walk '
                  'that passes through.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xxl),

                PrimaryButton(
                  label: creating ? 'Add zone' : 'Save zone',
                  expand: true,
                  large: true,
                  // Nothing to save until the map has a centre. Disabled rather
                  // than saving a guess.
                  onPressed: centre == null ? null : _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The fixed mark at the centre of the map. Non-interactive — [RouteMapView]
/// wraps its overlay in an `IgnorePointer`, so drags reach the map underneath.
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.onSurface.withValues(alpha: 0.65),
          border: Border.all(color: scheme.surface, width: 3),
        ),
      ),
    );
  }
}
