import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

/// A profile problem worth showing the person, phrased in the app's voice.
///
/// Mirrors `AuthFailure`: anything thrown as a [ProfileFailure] is safe — and
/// intended — to show inline. Everything else stays a raw exception and gets
/// the generic "that didn't save" copy.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The real `profiles` row, read and written through RLS.
///
/// This is the template the remaining de-mocks copy: the screens keep talking
/// to providers, the providers talk to a [ProfileRepository], and only this
/// file knows there is a Supabase client at all.
///
/// Three fields have no column behind them yet and are deliberately honest
/// rather than invented: [UserProfile.stats] is [LifetimeStats.empty] until the
/// activity engine exists, and the follower/following counts are zero until
/// there is a follow graph. [UserProfile.accentIndex] has no column by design —
/// it is derived from the id so the avatar tint is stable without storing it.
class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository();

  static const _columns =
      'id, full_name, avatar_url, role, status, created_at, handle, bio, parish';

  @override
  Future<UserProfile> profileById(String id) async {
    final row = await supabase
        .from('profiles')
        .select(_columns)
        .eq('id', id)
        .single();
    return _fromRow(row);
  }

  @override
  Future<UserProfile> updateProfile(String id, ProfileEdit edit) async {
    try {
      final row = await supabase
          .from('profiles')
          .update({
            'full_name': edit.displayName.trim(),
            'handle': _normaliseHandle(edit.handle),
            'bio': edit.bio.trim(),
            'parish': edit.parish.trim(),
          })
          .eq('id', id)
          .select(_columns)
          .single();
      return _fromRow(row);
    } on PostgrestException catch (error) {
      // 23505 = unique_violation. `handle` is the only unique column the app
      // writes, so this can only be a collision on it.
      if (error.code == '23505') {
        throw const ProfileFailure("That handle's taken — try another.");
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------- mapping ---

  UserProfile _fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final fullName = (row['full_name'] as String?)?.trim() ?? '';
    final handle = (row['handle'] as String?)?.trim() ?? '';

    return UserProfile(
      id: id,
      displayName: fullName.isEmpty ? 'Walker' : fullName,
      handle: handle.isEmpty ? _fallbackHandle(fullName) : _normaliseHandle(handle),
      bio: (row['bio'] as String?) ?? '',
      parish: (row['parish'] as String?) ?? '',
      role: (row['role'] as String?) == 'admin' ? UserRole.admin : UserRole.member,
      status: (row['status'] as String?) == 'suspended'
          ? MemberStatus.suspended
          : MemberStatus.active,
      joinedAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
      accentIndex: _accentFor(id),
    );
  }

  /// Stored with the leading `@`, whatever the person typed.
  static String _normaliseHandle(String value) {
    final bare = value.trim().replaceAll(RegExp(r'^@+'), '').trim();
    return '@$bare';
  }

  /// What to show when the row has no handle yet — a new account, since the
  /// new-user trigger doesn't set one. Derived, never written: it only becomes
  /// real if the person saves it from Edit profile.
  static String _fallbackHandle(String fullName) {
    final slug = fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return slug.isEmpty ? '@member' : '@$slug';
  }

  /// A stable avatar tint from the id. Same id, same colour, every launch and
  /// every device — which is the whole reason there is no column for it.
  static int _accentFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x1fffffff;
    }
    return hash % 6;
  }
}
