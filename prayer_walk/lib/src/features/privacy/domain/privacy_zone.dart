import 'package:latlong2/latlong.dart';

/// A place a walk must not be shown starting from or ending at.
///
/// Home, usually. Work, sometimes. A school gate, for anyone walking with
/// children. The rows live in `privacy_zones` and are readable by nobody but
/// their owner — not by other members, not through a join, and not by an admin.
/// A zone is, by construction, the single most sensitive fact a member gives
/// this app, because it is the place they most need a stranger not to have.
///
/// What it does is described in [PrivacyZone.explainer] rather than in a help
/// page: when anyone other than the owner reads a walk, the server drops the
/// points at either end of the trace that fall inside a zone before the
/// coordinates leave the database. The trimming is not a client-side filter and
/// could not be — see `activity_trace_for_viewer` in
/// `20260728090000_visibility_rls_and_reads.sql`.
class PrivacyZone {
  const PrivacyZone({
    required this.id,
    required this.label,
    required this.centre,
    required this.radiusMeters,
    required this.createdAt,
  });

  final String id;

  /// What the member calls it — "Home", "Mum's". Never leaves their account.
  final String label;

  final LatLng centre;
  final int radiusMeters;
  final DateTime createdAt;

  /// The default radius the editor opens at.
  ///
  /// 200 m covers a street and the corner at either end of it, which is what it
  /// takes to stop a trace resolving to one door, while still leaving an
  /// ordinary walk looking like a walk. Smaller and a trace that stops fifty
  /// metres short still points at the house; much larger and short walks
  /// disappear entirely.
  static const defaultRadiusMeters = 200;

  /// The floor and ceiling the check constraint enforces, repeated here so the
  /// slider cannot offer a value the database will refuse.
  static const minRadiusMeters = 50;
  static const maxRadiusMeters = 2000;

  /// Said in full, in plain language, on the screen where zones are created.
  /// A privacy control nobody understands is a privacy control nobody uses.
  static const explainer =
      'Walks you share are trimmed here. When someone else opens a walk of '
      'yours, the parts of the route inside this circle are removed before '
      'they reach their phone — so a walk that starts at your front door '
      'starts, for them, at the end of the street. You always see your own '
      'route in full. Nobody else can see where your zones are, including us.';

  PrivacyZone copyWith({String? label, LatLng? centre, int? radiusMeters}) =>
      PrivacyZone(
        id: id,
        label: label ?? this.label,
        centre: centre ?? this.centre,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        createdAt: createdAt,
      );
}

/// A zone being created or edited. [id] is null while it is still new.
class PrivacyZoneDraft {
  const PrivacyZoneDraft({
    this.id,
    this.label = 'Home',
    required this.centre,
    this.radiusMeters = PrivacyZone.defaultRadiusMeters,
  });

  PrivacyZoneDraft.from(PrivacyZone zone)
    : id = zone.id,
      label = zone.label,
      centre = zone.centre,
      radiusMeters = zone.radiusMeters;

  final String? id;
  final String label;
  final LatLng centre;
  final int radiusMeters;

  PrivacyZoneDraft copyWith({
    String? label,
    LatLng? centre,
    int? radiusMeters,
  }) => PrivacyZoneDraft(
    id: id,
    label: label ?? this.label,
    centre: centre ?? this.centre,
    radiusMeters: radiusMeters ?? this.radiusMeters,
  );
}
