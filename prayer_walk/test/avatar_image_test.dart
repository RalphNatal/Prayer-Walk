import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prayer_walk/src/features/profile/data/avatar_image.dart';

/// The avatar pipeline, tested on real JPEG bytes.
///
/// The GPS group is the one that matters. A photo taken with location services
/// on carries the coordinates of wherever it was taken in its EXIF block, and
/// for a lot of people that is their home — the same address this app trims off
/// the ends of a recorded walk so a route does not publish a doorstep. The
/// obvious decode-resize-encode pipeline round-trips those tags intact, because
/// `image`'s JPEG encoder writes `image.exif` back out whenever it is not
/// empty. So this is not a test that some flag is still set; it is a test that
/// bytes which went in with a latitude come out without one.

/// A photo carrying everything a phone camera writes: GPS, a make and model,
/// and an orientation tag claiming it needs a quarter turn.
///
/// Deliberately landscape and much larger than an avatar, so one fixture
/// exercises the crop and the resize as well.
Uint8List _photoWithGps({int width = 1200, int height = 800, int orientation = 1}) {
  final image = img.Image(width: width, height: height);
  // Not a flat fill: a solid colour compresses to almost nothing, which would
  // make the size assertions pass for the wrong reason. A gradient with noise
  // gives the encoder something to actually work at.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x * y) % 256);
    }
  }

  image.exif.imageIfd['Make'] = 'Prayer Walk Test Camera';
  image.exif.imageIfd['Model'] = 'Pixel Fixture';
  image.exif.imageIfd.orientation = orientation;
  // Antipolo, roughly — the coordinates a phone would stamp on a photo taken
  // at the top of the hill the fixtures elsewhere in this suite keep walking up.
  //
  // Written as explicit `IfdValue`s against the numeric tags, in the
  // degrees/minutes/seconds rationals a real camera uses. The obvious
  // `gpsIfd['GPSLatitude'] = ...` does not work and does not complain:
  // `IfdDirectory`'s string setter resolves the name to tag 0x0002 and then
  // types it against the *image* IFD table, where 0x0002 is not a GPS
  // coordinate — so the value is dropped on the floor. The control test below
  // exists for precisely that class of quiet nothing, which would otherwise
  // leave every assertion here passing over an empty fixture.
  image.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
  image.exif.gpsIfd[0x0002] = _dms(14, 35, 16);
  image.exif.gpsIfd[0x0003] = img.IfdValueAscii('E');
  image.exif.gpsIfd[0x0004] = _dms(121, 10, 33);

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// A GPS coordinate as the three rationals EXIF stores: degrees, minutes,
/// seconds.
///
/// Assembled by appending to the single-value constructor's list because
/// `image` does not export `Rational`, so `IfdValueRational.list` cannot be
/// called from outside the package.
img.IfdValueRational _dms(int degrees, int minutes, int seconds) {
  final value = img.IfdValueRational(degrees, 1);
  value.value
    ..addAll(img.IfdValueRational(minutes, 1).value)
    ..addAll(img.IfdValueRational(seconds, 1).value);
  return value;
}

void main() {
  group('prepareAvatar strips metadata', () {
    test('the fixture really does carry GPS, or the rest proves nothing', () {
      final decoded = img.decodeImage(_photoWithGps())!;

      expect(decoded.exif.gpsIfd.isEmpty, isFalse);
      expect(decoded.exif.imageIfd['Make']?.toString(), contains('Prayer Walk'));
    });

    test('no GPS survives the pipeline', () {
      final prepared = prepareAvatarSync(_photoWithGps());
      final out = img.decodeImage(prepared.bytes)!;

      expect(out.exif.gpsIfd.isEmpty, isTrue);
    });

    test('no EXIF at all survives — make, model, or anything else', () {
      final prepared = prepareAvatarSync(_photoWithGps());
      final out = img.decodeImage(prepared.bytes)!;

      expect(out.exif.isEmpty, isTrue);
      expect(out.exif.imageIfd['Make'], isNull);
      expect(out.exif.imageIfd['Model'], isNull);
    });

    test('the raw bytes carry no EXIF marker either', () {
      // Belt and braces on the assertions above: those read the output through
      // the same library that wrote it. This one looks for the `Exif\0\0`
      // signature in the file itself, which is what a metadata viewer — or
      // anyone who downloads the avatar — would find.
      final prepared = prepareAvatarSync(_photoWithGps());

      expect(_containsAscii(prepared.bytes, 'Exif'), isFalse);
      expect(_containsAscii(prepared.bytes, 'Prayer Walk Test Camera'), isFalse);
    });
  });

  group('prepareAvatar resizes and squares', () {
    test('a landscape photo comes back square', () {
      final prepared = prepareAvatarSync(_photoWithGps(width: 1200, height: 800));
      final out = img.decodeImage(prepared.bytes)!;

      expect(out.width, out.height);
    });

    test('a portrait photo comes back square', () {
      final prepared = prepareAvatarSync(_photoWithGps(width: 800, height: 1400));
      final out = img.decodeImage(prepared.bytes)!;

      expect(out.width, out.height);
    });

    test('the long edge is capped at 512', () {
      final prepared = prepareAvatarSync(_photoWithGps(width: 4032, height: 3024));

      expect(prepared.edge, 512);
    });

    test('a photo already smaller than the cap is not blown up', () {
      final prepared = prepareAvatarSync(_photoWithGps(width: 300, height: 300));

      expect(prepared.edge, 300);
    });

    test('the result lands well under 200 KB', () {
      final prepared = prepareAvatarSync(_photoWithGps(width: 4032, height: 3024));

      expect(prepared.sizeBytes, lessThan(200 * 1024));
    });

    test('a 12-megapixel original is reduced by orders of magnitude', () {
      final raw = _photoWithGps(width: 4032, height: 3024);
      final prepared = prepareAvatarSync(raw);

      // The guardrail is "do not upload originals". This is that, measured.
      expect(prepared.sizeBytes, lessThan(raw.length ~/ 10));
    });
  });

  group('prepareAvatar orientation', () {
    test('an orientation tag is applied to the pixels, not carried forward', () {
      // 6 means "rotate 90° clockwise to display". If the tag were simply
      // dropped along with the rest of the EXIF, the avatar would be stored
      // sideways — the failure mode that makes stripping metadata look like a
      // bug to the person whose face is now on its side.
      final prepared = prepareAvatarSync(
        _photoWithGps(width: 1200, height: 800, orientation: 6),
      );
      final out = img.decodeImage(prepared.bytes)!;

      expect(out.exif.imageIfd.hasOrientation, isFalse);
      expect(out.width, out.height);
    });
  });

  group('prepareAvatar rejects what it cannot use', () {
    test('a file that is not an image is refused in the app\'s voice', () {
      expect(
        () => prepareAvatarSync(Uint8List.fromList('not an image'.codeUnits)),
        throwsA(
          isA<AvatarImageFailure>().having(
            (e) => e.message,
            'message',
            contains("isn't an image"),
          ),
        ),
      );
    });
  });
}

/// Whether [bytes] contains [needle] as a run of ASCII. Enough to find an EXIF
/// segment header or a camera make left in a file.
bool _containsAscii(Uint8List bytes, String needle) {
  final target = needle.codeUnits;
  for (var i = 0; i + target.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < target.length; j++) {
      if (bytes[i + j] != target[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
