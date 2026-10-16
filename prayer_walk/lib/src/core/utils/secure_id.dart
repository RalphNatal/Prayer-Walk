import 'dart:math';
import 'dart:typed_data';

/// Seeded from the platform's secure entropy source rather than the clock, so
/// an object key cannot be guessed from one that was seen.
final _random = Random.secure();

/// A v4 uuid from the platform's secure RNG — `crypto.getRandomValues` on web,
/// `/dev/urandom` on mobile. Not `Random()`, whose sequence is guessable and
/// which would make a public Storage URL predictable from a neighbouring one.
///
/// Shared by every upload that names an object in a public bucket: a member's
/// avatar and a church group's images. The uuid is what makes those URLs
/// unguessable, so there is exactly one way to make one.
String secureUuidV4() {
  final bytes = Uint8List.fromList(
    List<int>.generate(16, (_) => _random.nextInt(256)),
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
