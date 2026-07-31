import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/profile_repository.dart';

/// Camera output → something worth putting in a bucket.
///
/// Four things happen to a photo here, and only one of them is about file size:
///
///   * the EXIF orientation is baked into the pixels, so a portrait photo is
///     still the right way up once the metadata is gone;
///   * it is cropped square, because every avatar in this app is drawn in a
///     circle and a rectangle would be centre-cropped by the widget anyway —
///     better to decide the framing once, here, than to store pixels nobody
///     ever sees;
///   * it is resized down to [_edge] and encoded as JPEG until it is under
///     [_maxBytes];
///   * **every EXIF tag is discarded**, which is the part that is not an
///     optimisation.
///
/// That last one needs saying plainly, because `image`'s JPEG encoder writes
/// `image.exif` back out if it is not empty, and `bakeOrientation` deliberately
/// copies the whole EXIF block forward minus the orientation tag. Decode,
/// resize, encode — the obvious pipeline — round-trips the GPS coordinates of
/// wherever the photo was taken. For a lot of people the answer is their home,
/// and this app trims the ends off recorded walks specifically so a route does
/// not publish a doorstep. Handing the same address back through an avatar
/// would undo that, quietly, in a file nobody thinks to look inside.
///
/// So the EXIF block is replaced with an empty one immediately before encoding,
/// and `avatar_image_test.dart` builds a JPEG carrying real GPS tags and
/// asserts they are gone from the output. That test is the guardrail; this
/// comment only explains it.

/// The long edge of a stored avatar. It is drawn at 96px at the very largest
/// (`AppSizes.avatarLg` with a ring), so 512 covers a 3x screen with room over
/// and there is nothing to gain from more.
const _edge = 512;

/// The size an encoded avatar has to come in under. Comfortably below the
/// bucket's own 512 KB ceiling, which is the backstop rather than the target —
/// a feed of twenty faces on mobile data is the thing being protected here.
const _maxBytes = 200 * 1024;

/// JPEG qualities to try, in order. The first one under [_maxBytes] wins. A
/// 512px face is nearly always well under at 82; the rest exist so a busy,
/// noisy photo degrades in quality rather than failing to upload.
const _qualityLadder = [82, 74, 66, 55];

/// A photo this app cannot use, phrased for the person holding it.
class AvatarImageFailure implements Exception {
  const AvatarImageFailure(this.message, {this.canOpenSettings = false});

  final String message;

  /// Whether the fix is in the system settings — a permission the OS refused,
  /// rather than a file that could not be read.
  ///
  /// Carried as a flag rather than inferred from the copy. The screen has to
  /// decide whether to offer a Settings button, and reading the wording to work
  /// that out means the button quietly disappears the day somebody rephrases
  /// the sentence.
  final bool canOpenSettings;

  @override
  String toString() => message;
}

/// Prepares [raw] for upload, off the UI isolate.
///
/// The work is pure Dart — decoding a 12-megapixel JPEG takes long enough to
/// drop frames, and the one thing worse than a slow upload is a frozen app
/// during it — so it runs through [compute]. Everything it touches is plain
/// bytes, which is what makes that legal.
Future<AvatarUpload> prepareAvatar(Uint8List raw) =>
    compute(prepareAvatarSync, raw);

/// The pipeline itself, synchronous and isolate-free so a test can call it
/// directly and read the bytes that come out.
@visibleForTesting
AvatarUpload prepareAvatarSync(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const AvatarImageFailure("That file isn't an image we can read.");
  }

  // Before anything measures width or height: an orientation tag can mean the
  // stored pixels are 90° from how the photo looks in the camera roll, and
  // cropping first would frame the wrong square.
  final upright = img.bakeOrientation(decoded);
  final square = _squareCrop(upright);
  final sized = square.width > _edge
      ? img.copyResize(
          square,
          width: _edge,
          height: _edge,
          interpolation: img.Interpolation.average,
        )
      : square;

  // The line this file exists for. `ExifData()` is empty, and the encoder skips
  // the APP1 segment entirely when it is — so the output carries no GPS, no
  // capture time, no camera serial, no thumbnail (which is its own leak: an
  // EXIF thumbnail is a second, uncropped copy of the picture).
  sized.exif = img.ExifData();

  for (final quality in _qualityLadder) {
    final bytes = img.encodeJpg(sized, quality: quality);
    if (bytes.length <= _maxBytes || quality == _qualityLadder.last) {
      return AvatarUpload(bytes: bytes, edge: sized.width);
    }
  }
  // Unreachable: the loop returns on its last iteration whatever the size.
  throw StateError('quality ladder exhausted without encoding');
}

/// The square this app keeps out of a rectangular photo.
///
/// Centred horizontally. Vertically it sits a third of the way down the excess
/// rather than halfway, because a portrait photo of a person is nearly always a
/// head near the top and a torso filling the rest — a true centre crop reliably
/// frames a chin and a shirt. On a landscape photo the bias does nothing, since
/// the excess is horizontal.
///
/// This is a heuristic standing in for a cropper, and it is a deliberate
/// omission rather than an oversight: `image_cropper` brings a UCrop activity
/// on Android and a pod on iOS, which is native build surface added to a
/// project that is one phase from a store submission. The requirement is a
/// square image, and this produces one. If members ask to choose their own
/// framing, that is the dependency to add, and it slots in ahead of
/// [prepareAvatar] without changing anything downstream.
img.Image _squareCrop(img.Image source) {
  final edge = source.width < source.height ? source.width : source.height;
  if (source.width == source.height) return source;

  final x = ((source.width - edge) / 2).round();
  final y = source.height > source.width
      ? ((source.height - edge) / 3).round()
      : 0;

  return img.copyCrop(source, x: x, y: y, width: edge, height: edge);
}
