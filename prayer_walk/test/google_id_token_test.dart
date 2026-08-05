import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/auth/domain/google_id_token.dart';

/// A JWT shaped exactly like a real Google ID token — three dot-separated,
/// unpadded base64url segments — but with a caller-chosen payload, so these
/// tests never need a real signed token to exercise the decoder.
String _fakeIdToken(Map<String, dynamic> payload) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment({
    'alg': 'RS256',
  })}.${segment(payload)}.signature';
}

void main() {
  group('decodeAudClaim', () {
    test('reads aud out of a well-formed payload', () {
      final token = _fakeIdToken({
        'aud': '123456789012-abc.apps.googleusercontent.com',
        'sub': 'user-1',
        'iss': 'https://accounts.google.com',
      });
      expect(
        GoogleIdToken.decodeAudClaim(token),
        '123456789012-abc.apps.googleusercontent.com',
      );
    });

    test('handles a payload whose base64url length needs padding restored', () {
      // A single-character claim value is the easiest way to land on a
      // segment length that is not already a multiple of 4.
      final token = _fakeIdToken({'aud': 'x'});
      expect(GoogleIdToken.decodeAudClaim(token), 'x');
    });

    test('null when the token is not three dot-separated segments', () {
      expect(GoogleIdToken.decodeAudClaim('not-a-jwt'), isNull);
      expect(GoogleIdToken.decodeAudClaim('only.two'), isNull);
      expect(GoogleIdToken.decodeAudClaim(''), isNull);
    });

    test('null when the middle segment is not valid base64url', () {
      expect(GoogleIdToken.decodeAudClaim('header.not!!valid**.sig'), isNull);
    });

    test('null when the payload does not decode to JSON', () {
      final bogus = base64Url.encode(utf8.encode('not json')).replaceAll('=', '');
      expect(GoogleIdToken.decodeAudClaim('header.$bogus.sig'), isNull);
    });

    test('null when the payload is JSON but has no aud claim', () {
      final token = _fakeIdToken({'sub': 'user-1'});
      expect(GoogleIdToken.decodeAudClaim(token), isNull);
    });

    test('null when aud is present but not a string', () {
      final token = _fakeIdToken({
        'aud': ['not-a-string'],
      });
      expect(GoogleIdToken.decodeAudClaim(token), isNull);
    });

    test('never needs the header or signature to be meaningful', () {
      // decodeAudClaim only ever reads segment [1] — garbage on either side
      // must not affect the result.
      final token = _fakeIdToken({'aud': 'still-readable'});
      final tampered = 'garbage-header.${token.split('.')[1]}.garbage-sig';
      expect(GoogleIdToken.decodeAudClaim(tampered), 'still-readable');
    });
  });
}
