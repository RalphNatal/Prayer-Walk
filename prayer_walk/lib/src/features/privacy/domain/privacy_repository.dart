import '../../profile/domain/user_profile.dart';
import 'activity_visibility.dart';
import 'privacy_zone.dart';

/// Everything a member controls about who can reach them.
///
/// Three groups, kept behind one interface because they are one decision from
/// the member's side — "who sees me, from where, and who is shut out" — and
/// because the screen that presents them is one screen.
abstract interface class PrivacyRepository {
  // ------------------------------------------------------------- defaults ---

  /// The visibility a new walk starts at, from `profiles`.
  Future<ActivityVisibility> defaultVisibility();

  Future<void> setDefaultVisibility(ActivityVisibility visibility);

  /// Whether this member has already been shown the "everyone can see this"
  /// explanation. Stored server-side rather than on the device: the
  /// consequence it explains is server-side, and it should not reappear on a
  /// second phone or vanish on a reinstall.
  Future<bool> publicWalkNoticeSeen();

  Future<void> markPublicWalkNoticeSeen();

  /// Changes one walk's audience. Scoped to the owner by RLS — a call against
  /// somebody else's walk matches no rows and changes nothing.
  Future<void> setActivityVisibility(
    String activityId,
    ActivityVisibility visibility,
  );

  // ---------------------------------------------------------------- zones ---

  /// The signed-in member's own zones. There is no method for anybody else's,
  /// and there could not be: `privacy_zones` is owner-only for read.
  Future<List<PrivacyZone>> zones();

  /// Creates when [draft.id] is null, otherwise updates in place.
  Future<PrivacyZone> saveZone(PrivacyZoneDraft draft);

  Future<void> deleteZone(String id);

  // --------------------------------------------------------------- blocks ---

  Future<List<UserProfile>> blockedMembers();

  Future<bool> isBlocked(String otherId);

  /// Blocks or unblocks. Returns whether [otherId] is now blocked.
  ///
  /// Blocking also severs any follow in either direction — done by a trigger on
  /// `blocks`, so it happens whether the app remembers to ask or not.
  Future<bool> toggleBlock(String otherId);
}
