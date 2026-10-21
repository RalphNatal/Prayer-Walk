import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prayer_walk/src/features/auth/data/auth_repository.dart';
import 'package:prayer_walk/src/features/auth/domain/apple_nonce.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

const _userId = 'b6f3e1a2-0000-4000-8000-0000000000aa';
const _appleSub = '001234.5b6c7d8e9f.0123';
const _relayEmail = 'k7x2q9mnzp@privaterelay.appleid.com';

/// A Supabase project reduced to the five endpoints these flows touch, which
/// records every request so a test can read exactly what was sent — the raw
/// nonce in the ID-token exchange, the filter on the profile write, the body
/// of the `delete-account` call.
class _Backend {
  _Backend({
    this.email = 'walker@example.com',
    this.provider = 'apple',
    this.rejectIdToken = false,
  });

  final String email;
  final String provider;
  final bool rejectIdToken;

  final requests = <http.Request>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final response = _respond(request);
    // A real client always attaches the request; postgrest reads it back.
    return http.Response(
      response.body,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  });

  http.Response _respond(http.Request request) {
    final path = request.url.path;
    if (path == '/auth/v1/token') {
      if (rejectIdToken) {
        return _json({
          'code': 400,
          'error_code': 'bad_jwt',
          'msg': 'Nonces mismatch',
        }, 400);
      }
      return _json(_session(), 200);
    }
    if (path == '/rest/v1/profiles' && request.method == 'PATCH') {
      return http.Response('', 204);
    }
    if (path == '/rest/v1/profiles' && request.method == 'GET') {
      return _json({
        'id': _userId,
        'full_name': 'Maria Reyes',
        'avatar_url': null,
        'role': 'member',
      }, 200);
    }
    if (path == '/functions/v1/delete-account') return _json({'ok': true}, 200);
    if (path == '/auth/v1/logout') return http.Response('', 204);
    return http.Response('unexpected ${request.method} $path', 500);
  }

  Map<String, dynamic> _session() => {
    // Not a JWT, so gotrue reads no expiry from it and never tries a refresh.
    'access_token': 'member-access-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'member-refresh-token',
    'user': {
      'id': _userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'created_at': '2026-10-21T00:00:00Z',
      'app_metadata': {
        'provider': provider,
        'providers': [provider],
      },
      'user_metadata': <String, dynamic>{},
      'identities': [
        {
          'id': provider == 'apple' ? _appleSub : _userId,
          'identity_id': 'c0ffee00-0000-4000-8000-000000000001',
          'user_id': _userId,
          'provider': provider,
          'identity_data': {'sub': _appleSub, 'email': email},
        },
      ],
    },
  };

  static http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Request get idTokenExchange => requests.singleWhere(
    (r) =>
        r.url.path == '/auth/v1/token' &&
        r.url.queryParameters['grant_type'] == 'id_token',
  );

  Iterable<http.Request> get profileWrites => requests.where(
    (r) => r.url.path == '/rest/v1/profiles' && r.method == 'PATCH',
  );

  Iterable<http.Request> get deleteCalls =>
      requests.where((r) => r.url.path == '/functions/v1/delete-account');
}

/// Stands in for Apple's sheet. Records the scopes and nonce it was asked
/// for — the only place the hashed half of the nonce is visible — and hands
/// back whatever the test scripted.
class _FakeApple {
  _FakeApple({
    this.givenName,
    this.familyName,
    this.identityToken = 'apple.identity.token',
  });

  final String? givenName;
  final String? familyName;
  final String? identityToken;

  /// Thrown by the next request instead of a credential, when set.
  Object? error;

  final requests = <({List<AppleIDAuthorizationScopes> scopes, String? nonce})>[];

  Future<AuthorizationCredentialAppleID> call({
    required List<AppleIDAuthorizationScopes> scopes,
    String? nonce,
  }) async {
    requests.add((scopes: scopes, nonce: nonce));
    final scripted = error;
    if (scripted != null) throw scripted;
    return AuthorizationCredentialAppleID(
      userIdentifier: _appleSub,
      givenName: givenName,
      familyName: familyName,
      authorizationCode: 'fresh-code-${requests.length}',
      email: null,
      identityToken: identityToken,
      state: null,
    );
  }
}

SignInWithAppleAuthorizationException _appleError(AuthorizationErrorCode code) =>
    SignInWithAppleAuthorizationException(code: code, message: 'from iOS');

void main() {
  late _Backend backend;
  late _FakeApple apple;
  late SupabaseClient client;
  late AuthRepository repository;
  late DebugPrintCallback originalDebugPrint;

  void build({_Backend? withBackend, _FakeApple? withApple}) {
    backend = withBackend ?? _Backend();
    apple = withApple ?? _FakeApple();
    client = SupabaseClient(
      'https://project.supabase.co',
      'anon-key',
      httpClient: backend.client,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = AuthRepository(
      client: client,
      requestAppleCredential: apple.call,
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // The stage log is the point of the real flow and noise in a test run.
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    build();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    debugPrint = originalDebugPrint;
    await client.dispose();
  });

  group('AppleNonce', () {
    test('hashed is the lowercase SHA-256 hex of raw', () {
      final nonce = AppleNonce.fromRaw('abc');
      expect(nonce.raw, 'abc');
      expect(
        nonce.hashed,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('generate() is fresh every time, and URL-safe', () {
      final a = AppleNonce.generate();
      final b = AppleNonce.generate();
      expect(a.raw, hasLength(32));
      expect(a.raw, isNot(b.raw));
      expect(a.raw, matches(RegExp(r'^[0-9A-Za-z\-._]+$')));
      expect(a.hashed, sha256.convert(utf8.encode(a.raw)).toString());
    });
  });

  group('the nonce contract', () {
    test('Apple is handed the SHA-256 hash; Supabase the raw value', () async {
      await repository.signInWithApple();

      final exchange =
          jsonDecode(backend.idTokenExchange.body) as Map<String, dynamic>;
      final raw = exchange['nonce'] as String;
      final toApple = apple.requests.single.nonce;

      expect(exchange['provider'], 'apple');
      expect(exchange['id_token'], 'apple.identity.token');
      expect(toApple, sha256.convert(utf8.encode(raw)).toString());
      // The failure this guards against: the two crossed over, or the same
      // value sent to both.
      expect(raw, isNot(toApple));
    });

    test('a fresh nonce for every attempt', () async {
      await repository.signInWithApple();
      await repository.signInWithApple();

      expect(apple.requests, hasLength(2));
      expect(apple.requests[0].nonce, isNot(apple.requests[1].nonce));
    });

    test('asks Apple for the email and name scopes', () async {
      await repository.signInWithApple();

      expect(apple.requests.single.scopes, [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ]);
    });
  });

  group('the name Apple sends once', () {
    test('first authorisation writes it into an empty profile name', () async {
      build(withApple: _FakeApple(givenName: 'Maria', familyName: 'Reyes'));

      await repository.signInWithApple();

      final write = backend.profileWrites.single;
      expect(jsonDecode(write.body), {'full_name': 'Maria Reyes'});
      expect(write.url.queryParameters['id'], 'eq.$_userId');
      // Only over an empty name: a member who has since chosen their own
      // display name keeps it if Apple ever sends the name again.
      expect(write.url.queryParameters['full_name'], 'eq.');
    });

    test('a later sign-in, which carries no name, writes nothing at all', () async {
      build(withApple: _FakeApple());

      await repository.signInWithApple();

      expect(backend.profileWrites, isEmpty);
    });

    test('a name cleared on Apple\'s sheet is treated as no name', () async {
      build(withApple: _FakeApple(givenName: '  ', familyName: ''));

      await repository.signInWithApple();

      expect(backend.profileWrites, isEmpty);
    });

    test('either half alone is still a name', () {
      expect(AuthRepository.appleFullName('Maria', null), 'Maria');
      expect(AuthRepository.appleFullName(null, 'Reyes'), 'Reyes');
      expect(AuthRepository.appleFullName(' Maria ', ' Reyes '), 'Maria Reyes');
      expect(AuthRepository.appleFullName(null, null), isNull);
    });

    test('is held to the same length the Edit profile form allows', () {
      final name = AuthRepository.appleFullName('A' * 50, 'B' * 50);
      expect(name, hasLength(60));
    });
  });

  group('cancelling', () {
    test('a dismissed sheet is AuthCancelled, and nothing reaches Supabase', () async {
      apple.error = _appleError(AuthorizationErrorCode.canceled);

      await expectLater(
        repository.signInWithApple(),
        throwsA(isA<AuthCancelled>()),
      );
      expect(backend.requests, isEmpty);
    });

    test('a real failure is an AuthFailure, not a cancel', () async {
      apple.error = _appleError(AuthorizationErrorCode.failed);

      await expectLater(
        repository.signInWithApple(),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'failed')),
      );
    });

    test('"unknown" names the device, not the network', () async {
      apple.error = _appleError(AuthorizationErrorCode.unknown);

      await expectLater(
        repository.signInWithApple(),
        throwsA(
          isA<AuthFailure>()
              .having((f) => f.code, 'code', 'unknown')
              .having((f) => f.message, 'message', contains('Apple ID')),
        ),
      );
    });
  });

  group('failures after Apple', () {
    test('no identity token stops before Supabase', () async {
      build(withApple: _FakeApple(identityToken: null));

      await expectLater(
        repository.signInWithApple(),
        throwsA(
          isA<AuthFailure>().having((f) => f.code, 'code', 'missingIdToken'),
        ),
      );
      expect(backend.requests, isEmpty);
    });

    test('Supabase turning the token away is a coded AuthFailure', () async {
      build(withBackend: _Backend(rejectIdToken: true));

      await expectLater(
        repository.signInWithApple(),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.code,
            'code',
            startsWith('supabase:'),
          ),
        ),
      );
    });
  });

  group('platform', () {
    test('off iOS it fails plainly and never opens Apple\'s sheet', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(AuthRepository.offersAppleSignIn, isFalse);
      await expectLater(
        repository.signInWithApple(),
        throwsA(
          isA<AuthFailure>().having((f) => f.code, 'code', 'unsupportedPlatform'),
        ),
      );
      expect(apple.requests, isEmpty);
    });
  });

  group('private relay email', () {
    test('is a real address: signs in, and the profile reads as normal', () async {
      build(
        withBackend: _Backend(email: _relayEmail),
        withApple: _FakeApple(givenName: 'Maria', familyName: 'Reyes'),
      );

      await repository.signInWithApple();

      expect(repository.currentUser?.email, _relayEmail);
      expect(backend.profileWrites, hasLength(1));
      final profile = await repository.fetchProfile(_userId);
      expect(profile.id, _userId);
    });
  });

  group('deleting an account', () {
    test('an Apple account sends a fresh Apple code to delete-account', () async {
      await repository.signInWithApple();
      expect(repository.isAppleAccount, isTrue);

      await repository.deleteAccount();

      // The second request to Apple: no scopes and no nonce, only a code.
      final reauth = apple.requests.last;
      expect(reauth.scopes, isEmpty);
      expect(reauth.nonce, isNull);
      expect(jsonDecode(backend.deleteCalls.single.body), {
        'apple_authorization_code': 'fresh-code-2',
      });
    });

    test('dismissing Apple\'s sheet cancels the deletion before it starts', () async {
      await repository.signInWithApple();
      apple.error = _appleError(AuthorizationErrorCode.canceled);

      await expectLater(
        repository.deleteAccount(),
        throwsA(isA<AuthCancelled>()),
      );
      expect(backend.deleteCalls, isEmpty);
    });

    test('any other Apple failure still deletes, without a code', () async {
      await repository.signInWithApple();
      apple.error = _appleError(AuthorizationErrorCode.unknown);

      await repository.deleteAccount();

      expect(backend.deleteCalls.single.body, isEmpty);
    });

    test('an account without Apple never sees Apple\'s sheet', () async {
      build(withBackend: _Backend(provider: 'email'));
      await repository.signInWithEmail(email: 'w@example.com', password: 'pw');
      expect(repository.isAppleAccount, isFalse);

      await repository.deleteAccount();

      expect(apple.requests, isEmpty);
      expect(backend.deleteCalls.single.body, isEmpty);
    });
  });
}
