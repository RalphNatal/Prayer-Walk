import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_exception.dart';
import '../../profile/data/profile_row_mapper.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/activity_visibility.dart';
import '../domain/privacy_repository.dart';
import '../domain/privacy_zone.dart';

/// The `privacy_zones` columns a read needs, kept next to the mapper below for
/// the reason `activityColumns` is kept next to its own.
const privacyZoneColumns = 'id, label, lat, lng, radius_meters, created_at';

/// Visibility settings, privacy zones and blocks, through RLS.
///
/// Nothing in this class enforces anything. Every rule it appears to apply —
/// that a zone belongs to one member, that a block binds both parties, that a
/// walk's audience is its owner's to set — is a policy in
/// `20260728080000_visibility_zones_blocks.sql`. What is here is the shape of
/// the request and the sentence shown when it is refused.
class SupabasePrivacyRepository implements PrivacyRepository {
  const SupabasePrivacyRepository(this._userId);

  /// Whose settings these are. Null while signed out, which every method below
  /// treats as "there is nothing to read" rather than as an error — the
  /// providers are watched by screens that can outlive a session by a frame.
  final String? _userId;

  // ------------------------------------------------------------- defaults ---

  @override
  Future<ActivityVisibility> defaultVisibility() async {
    final id = _userId;
    if (id == null) return ActivityVisibility.standard;

    final row = await supabase
        .from('profiles')
        .select('default_activity_visibility')
        .eq('id', id)
        .maybeSingle();

    return ActivityVisibility.fromWire(
      row?['default_activity_visibility'] as String?,
    );
  }

  @override
  Future<void> setDefaultVisibility(ActivityVisibility visibility) async {
    final id = _userId;
    if (id == null) return;
    await supabase
        .from('profiles')
        .update({'default_activity_visibility': visibility.wireName})
        .eq('id', id);
  }

  @override
  Future<bool> publicWalkNoticeSeen() async {
    final id = _userId;
    if (id == null) return true;
    final row = await supabase
        .from('profiles')
        .select('public_walk_notice_seen')
        .eq('id', id)
        .maybeSingle();
    return (row?['public_walk_notice_seen'] as bool?) ?? false;
  }

  @override
  Future<void> markPublicWalkNoticeSeen() async {
    final id = _userId;
    if (id == null) return;
    await supabase
        .from('profiles')
        .update({'public_walk_notice_seen': true})
        .eq('id', id);
  }

  @override
  Future<void> setActivityVisibility(
    String activityId,
    ActivityVisibility visibility,
  ) async {
    final rows = await supabase
        .from('activities')
        .update({'visibility': visibility.wireName})
        .eq('id', activityId)
        .select('id');
    // The update policy is `auth.uid() = user_id`, so somebody else's walk
    // matches nothing and reports success. Saying so is the difference between
    // a refusal and a silent no-op — the shape the admin-role migration called
    // the worst a security failure can take.
    if (rows.isEmpty) throw AppException.notFound;
  }

  // ---------------------------------------------------------------- zones ---

  @override
  Future<List<PrivacyZone>> zones() async {
    final id = _userId;
    if (id == null) return const [];

    // No `.eq('user_id', ...)`. The SELECT policy is owner-only, so this reads
    // the caller's zones and nothing else by construction. Adding the filter
    // would imply the filter is what makes it safe.
    final rows = await supabase
        .from('privacy_zones')
        .select(privacyZoneColumns)
        .order('created_at', ascending: true);

    return [for (final row in rows) privacyZoneFromRow(row)];
  }

  @override
  Future<PrivacyZone> saveZone(PrivacyZoneDraft draft) async {
    final id = _userId;
    if (id == null) {
      throw const AppException('Sign in again, then set your zone.');
    }

    final label = draft.label.trim();
    if (label.isEmpty) {
      throw const AppException('Give the zone a name — "Home" will do.');
    }

    final payload = {
      'user_id': id,
      'label': label,
      'lat': draft.centre.latitude,
      'lng': draft.centre.longitude,
      'radius_meters': draft.radiusMeters.clamp(
        PrivacyZone.minRadiusMeters,
        PrivacyZone.maxRadiusMeters,
      ),
    };

    final zoneId = draft.id;
    final row = zoneId == null
        ? await supabase
              .from('privacy_zones')
              .insert(payload)
              .select(privacyZoneColumns)
              .single()
        : await supabase
              .from('privacy_zones')
              .update(payload)
              .eq('id', zoneId)
              .select(privacyZoneColumns)
              .single();

    return privacyZoneFromRow(row);
  }

  @override
  Future<void> deleteZone(String id) async {
    await supabase.from('privacy_zones').delete().eq('id', id);
  }

  // --------------------------------------------------------------- blocks ---

  @override
  Future<List<UserProfile>> blockedMembers() async {
    final id = _userId;
    if (id == null) return const [];

    final rows = await supabase
        .from('blocks')
        .select('blocked:profiles!blocks_blocked_id_fkey($profileColumns)')
        .eq('blocker_id', id)
        .order('created_at', ascending: false);

    return [
      for (final row in rows)
        if (row['blocked'] != null)
          userProfileFromRow(row['blocked'] as Map<String, dynamic>),
    ];
  }

  @override
  Future<bool> isBlocked(String otherId) async {
    final id = _userId;
    if (id == null || id == otherId) return false;
    final row = await supabase
        .from('blocks')
        .select('blocker_id')
        .eq('blocker_id', id)
        .eq('blocked_id', otherId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<bool> toggleBlock(String otherId) async {
    final id = _userId;
    if (id == null) {
      throw const AppException('Sign in again, then try that.');
    }
    if (id == otherId) {
      throw const AppException("You can't block yourself.");
    }

    if (await isBlocked(otherId)) {
      await supabase
          .from('blocks')
          .delete()
          .eq('blocker_id', id)
          .eq('blocked_id', otherId);
      return false;
    }

    try {
      await supabase.from('blocks').insert({
        'blocker_id': id,
        'blocked_id': otherId,
      });
    } on PostgrestException catch (error) {
      // 23505 on the primary key: already blocked, which is the state the
      // caller is being told about. Same bargain as the follow toggle.
      if (error.code != '23505') rethrow;
    }
    return true;
  }
}

/// Row → [PrivacyZone]. Small enough to live with the repository; there is only
/// one query shape and one direction that matters.
PrivacyZone privacyZoneFromRow(Map<String, dynamic> row) => PrivacyZone(
  id: (row['id'] ?? '').toString(),
  label: ((row['label'] as String?)?.trim().isNotEmpty ?? false)
      ? (row['label'] as String).trim()
      : 'Zone',
  centre: LatLng(
    (row['lat'] as num?)?.toDouble() ?? 0,
    (row['lng'] as num?)?.toDouble() ?? 0,
  ),
  radiusMeters:
      (row['radius_meters'] as num?)?.toInt() ??
      PrivacyZone.defaultRadiusMeters,
  createdAt:
      DateTime.tryParse((row['created_at'] as String?) ?? '')?.toLocal() ??
      DateTime.now(),
);
