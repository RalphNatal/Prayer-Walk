import '../../profile/domain/user_profile.dart';

/// The signed-in user's `profiles` row — the server-authoritative identity and
/// role.
///
/// This is provisioned server-side by the new-user trigger (Part A), never by
/// the app. The app only ever reads it: [role] decides which shell you land in,
/// and it is the DB — RLS plus the self-promotion guard — that enforces the
/// gate. The redirect that reads [role] is convenience, not the boundary.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final UserRole role;

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      role: _roleFrom(map['role'] as String?),
    );
  }

  /// Unknown or absent roles fall back to the least-privileged one. The server
  /// is the real gate, so a wrong guess here can only ever under-grant.
  static UserRole _roleFrom(String? value) =>
      value == 'admin' ? UserRole.admin : UserRole.member;

  bool get isAdmin => role == UserRole.admin;
}
