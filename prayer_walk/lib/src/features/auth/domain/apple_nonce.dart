import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The two halves of one Sign in with Apple nonce, and which way each goes.
///
/// Apple puts whatever nonce it is handed into the identity token's `nonce`
/// claim, unchanged (the plugin passes it straight to
/// `ASAuthorizationAppleIDRequest.nonce`). Supabase, given a nonce alongside
/// that token, hashes it and compares the hash with the claim. So:
///
/// * [hashed] — the SHA-256 hex digest — goes to **Apple**;
/// * [raw] goes to **Supabase**, which does the hashing itself.
///
/// Crossed over, every sign-in fails with an opaque "nonce mismatch" from
/// Supabase and nothing to say which side is wrong. The two getters are named
/// for what they are rather than where they go, so that a call site reading
/// `nonce: nonce.hashed` into Supabase looks as wrong as it is.
@immutable
class AppleNonce {
  AppleNonce._(this.raw) : hashed = sha256.convert(utf8.encode(raw)).toString();

  /// A fresh nonce from [Random.secure], one per sign-in attempt.
  factory AppleNonce.generate({int length = 32}) {
    final random = Random.secure();
    return AppleNonce._(
      List.generate(
        length,
        (_) => _charset[random.nextInt(_charset.length)],
      ).join(),
    );
  }

  /// A nonce built from a known value, so a test can predict both halves.
  @visibleForTesting
  factory AppleNonce.fromRaw(String raw) => AppleNonce._(raw);

  /// Unreserved URL characters only, so the value survives any encoding a
  /// request might put it through on its way to either side.
  static const _charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

  /// The value Supabase is given, and hashes itself.
  final String raw;

  /// The lowercase SHA-256 hex digest of [raw]: the value Apple is given.
  final String hashed;
}
