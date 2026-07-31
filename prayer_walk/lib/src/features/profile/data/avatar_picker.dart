import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'avatar_image.dart';

/// Where a profile photo comes from.
enum AvatarSource { camera, gallery }

/// The only file in the app that imports `image_picker`.
///
/// Same shape as `LocationService`: the plugin lives behind an interface so the
/// screen depends on "give me some bytes" rather than on a platform channel,
/// and so a test can supply bytes without a camera. `prepareAvatar` is not
/// called here — picking and processing are separate steps because the screen
/// wants to show progress between them.
abstract interface class AvatarPicker {
  /// Bytes of the picked photo, or null if the person backed out.
  ///
  /// Throws [AvatarImageFailure] when the pick was refused rather than
  /// cancelled, so the caller can tell "changed my mind" from "the OS said no"
  /// and only offer Settings for the second.
  Future<Uint8List?> pick(AvatarSource source);

  /// Opens this app's page in the system settings, for a permission that was
  /// denied permanently and can only be granted there.
  Future<void> openSettings();
}

class ImagePickerAvatarPicker implements AvatarPicker {
  ImagePickerAvatarPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// A cheap native pre-shrink before the Dart pipeline sees the file.
  ///
  /// Well above the 512px an avatar ends up at, so nothing about the final
  /// image depends on this number — it exists so `prepareAvatar` decodes a
  /// 2.5-megapixel buffer instead of a 12-megapixel one, which is the
  /// difference between a moment and a stall on a cheap phone.
  ///
  /// It is explicitly *not* the privacy step. `image_picker` copies the
  /// original EXIF onto the resized file on Android — deliberately, so
  /// orientation survives — and normalises on iOS. Either way the tags that
  /// matter are stripped in `prepareAvatar`, which is the one place that is
  /// tested for it.
  static const _preShrinkEdge = 1600.0;

  @override
  Future<Uint8List?> pick(AvatarSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == AvatarSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: _preShrinkEdge,
        maxHeight: _preShrinkEdge,
        // The camera's own front/rear choice, not a preference this app has an
        // opinion about.
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on PlatformException catch (error) {
      throw _refusal(error, source);
    }
  }

  /// What the plugin says when the OS refused, turned into a sentence.
  ///
  /// The codes are `image_picker`'s own. Anything unrecognised keeps a neutral
  /// line and no Settings button — the same rule the shared error mapper
  /// follows, for the same reason: an app that guesses at a cause sends people
  /// to fix things that were never broken.
  AvatarImageFailure _refusal(PlatformException error, AvatarSource source) {
    return switch (error.code) {
      'camera_access_denied' => const AvatarImageFailure(
        'Prayer Walk needs camera access to take a photo. '
            'You can turn it on in Settings.',
        canOpenSettings: true,
      ),
      'photo_access_denied' => const AvatarImageFailure(
        'Prayer Walk needs photo access to choose a picture. '
            'You can turn it on in Settings.',
        canOpenSettings: true,
      ),
      _ => AvatarImageFailure(
        source == AvatarSource.camera
            ? "The camera didn't open."
            : "Your photos didn't open.",
      ),
    };
  }

  /// `permission_handler` is already in this project for the pedometer and the
  /// location prompts; this is the same one call it is used for there. Note the
  /// deliberate absence of any `request()` — `image_picker` asks for what it
  /// needs, when it needs it, and a second asker is how an app ends up with two
  /// dialogs and one grant.
  @override
  Future<void> openSettings() => ph.openAppSettings();
}
