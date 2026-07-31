import 'dart:typed_data';

import 'user_profile.dart';

/// The fields the member can change on Edit profile.
///
/// Every field here is public — `profiles` is readable by any signed-in member,
/// which is what the feed byline and discovery are built on. The form says so
/// rather than letting someone assume a quieter field exists.
///
/// `role` and `status` are deliberately absent and must stay that way: they are
/// guarded server-side by the self-promotion trigger and the admin policy, and
/// this class is the reason the app never has cause to send them.
///
/// The photo is not here. It moves through [ProfileRepository.uploadAvatar] and
/// [ProfileRepository.removeAvatar] instead, because it is bytes rather than a
/// form value and because it has to survive a failure independently: a photo
/// that fails to upload must leave the previous one — and the rest of the
/// form — untouched.
class ProfileEdit {
  const ProfileEdit({
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.parish,
    this.pronouns = '',
    this.location = '',
    this.links = '',
  });

  final String displayName;
  final String handle;
  final String bio;
  final String parish;

  /// Short and free — "she/her", "they/them".
  final String pronouns;

  /// City-level free text. Never coordinates: see the column comment in
  /// `20260731010000_profile_public_fields.sql`.
  final String location;

  /// One URL, scheme-checked by `profileLink` before it gets this far.
  final String links;
}

/// A profile photo that has already been through the pipeline: square, small,
/// and stripped of everything the camera wrote around the pixels.
///
/// Built only by `prepareAvatar`. The repository takes this rather than a raw
/// `Uint8List` so there is no signature in the app that will accept an
/// unprocessed camera file — the EXIF rule is enforced by the type, not by
/// remembering to call something first.
class AvatarUpload {
  const AvatarUpload({required this.bytes, required this.edge});

  /// JPEG, no EXIF, no GPS.
  final Uint8List bytes;

  /// Width and height in pixels — square, so one number.
  final int edge;

  /// What the size cap is actually judged against, for the log line and the
  /// tests.
  int get sizeBytes => bytes.length;
}

abstract interface class ProfileRepository {
  Future<UserProfile> profileById(String id);

  Future<UserProfile> updateProfile(String id, ProfileEdit edit);

  /// Stores [upload] as [id]'s avatar and points the profile row at it.
  ///
  /// Implementations must leave the previous photo in place if anything here
  /// fails: the row is only re-pointed once the new object is written, and the
  /// old object is only swept once the row no longer refers to it. A member who
  /// loses signal mid-upload keeps the face they had.
  Future<UserProfile> uploadAvatar(String id, AvatarUpload upload);

  /// Clears `avatar_url` and deletes the stored object, falling the profile
  /// back to its initials.
  Future<UserProfile> removeAvatar(String id);
}
