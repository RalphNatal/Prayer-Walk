import 'user_profile.dart';

/// The fields the member can change on Edit profile.
class ProfileEdit {
  const ProfileEdit({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.parish,
  });

  final String displayName;
  final String handle;
  final String bio;
  final String parish;
}

abstract interface class ProfileRepository {
  Future<UserProfile> profileById(String id);

  Future<UserProfile> updateProfile(String id, ProfileEdit edit);
}
