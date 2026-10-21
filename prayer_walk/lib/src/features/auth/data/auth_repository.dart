import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_logger.dart';
import '../../profile/domain/profile_fields.dart';
import '../domain/apple_nonce.dart';
import '../domain/profile.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code, this.details, this.stackTrace});

  final String message;
  final String? code;
  final String? details;
  final StackTrace? stackTrace;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Puts Apple's sign-in sheet on screen and returns what it hands back —
/// [SignInWithApple.getAppleIDCredential] in the app.
typedef AppleCredentialRequest =
    Future<AuthorizationCredentialAppleID> Function({
      required List<AppleIDAuthorizationScopes> scopes,
      String? nonce,
    });

/// All authentication against Supabase, plus native Google via google_sign_in
/// v7 and native Apple via sign_in_with_apple. The rest of the app talks to
/// this, never to the SDK directly.
class AuthRepository {
  /// Both parameters exist for tests, and the app passes neither.
  ///
  /// [client] replaces the app's one initialized Supabase client — a test
  /// builds one over a fake HTTP transport, so it can read exactly what was
  /// sent. [requestAppleCredential] replaces Apple's sheet, which is the only
  /// way to see which nonce Apple was handed.
  AuthRepository({
    SupabaseClient? client,
    AppleCredentialRequest? requestAppleCredential,
  }) : _clientOverride = client,
       _requestAppleCredential =
           requestAppleCredential ?? SignInWithApple.getAppleIDCredential;

  final SupabaseClient? _clientOverride;
  final AppleCredentialRequest _requestAppleCredential;

  /// A getter, like [supabase] itself: nothing may touch `Supabase.instance`
  /// before `main` has initialized it.
  SupabaseClient get _client => _clientOverride ?? supabase;

  // ------------------------------------------------------------- session ---

  /// Supabase auth events — `initialSession`, `signedIn`, `signedOut`, token
  /// refreshes. `supabase_flutter` persists and restores the session itself, so
  /// this replays the restored session to new listeners on launch.
  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  // --------------------------------------------------------------- email ---

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw AuthFailure(_emailMessage(error));
    }
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final name = fullName?.trim();
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Passed to the new-user trigger via user metadata, so an email sign-up
        // gets a name on its profile just like a Google one does.
        data: (name != null && name.isNotEmpty) ? {'full_name': name} : null,
      );
      // With email confirmation enabled, sign-up returns no session; the person
      // has to confirm first. Surface that rather than silently doing nothing.
      if (response.session == null && response.user != null) {
        throw const AuthFailure(
          'Almost there — check your email to confirm your account, then sign in.',
        );
      }
      return response;
    } on AuthException catch (error) {
      throw AuthFailure(_emailMessage(error));
    }
  }

  /// The profiles row for [userId], provisioned server-side by the new-user
  /// trigger. Retries once: on a first Google sign-in the auth user and the
  /// trigger-inserted row land in quick succession, and the read can just beat
  /// the insert.
  Future<Profile> fetchProfile(String userId) async {
    for (var attempt = 0; ; attempt++) {
      final row = await _client
          .from('profiles')
          .select('id, full_name, avatar_url, role')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) return Profile.fromMap(row);
      if (attempt >= 2) {
        // The read succeeded and came back empty three times: the row is not
        // there. Nothing about that is the connection, and saying it was sent
        // people to check their wifi over a trigger that had not fired.
        throw const AuthFailure(
          "Your profile hasn't finished setting up. Sign in again in a moment.",
          code: 'profile_row_missing',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  // ----------------------------------------------------------- deletion ---

  static const _deletionTag = 'PW-DELETE';

  /// Deletes the signed-in member's own account and everything that belongs
  /// to it, via the `delete-account` Edge Function — see its own doc comment
  /// for exactly what that covers. The function derives the account to delete
  /// from the caller's own verified session token; there is no id to pass.
  ///
  /// An account that signed in with Apple first asks Apple for one fresh
  /// authorization code and sends it along, so the function can revoke the
  /// app's Apple token — see [_appleCodeForRevocation]. Dismissing Apple's
  /// sheet throws [AuthCancelled] before anything has been deleted.
  ///
  /// Always finishes by clearing the local session, even though the server
  /// side has already made it unusable — the point is the app's own state
  /// (cached session, in-memory user) does not outlive the account by even
  /// one frame. A [SignOutScope.local] sign-out is used deliberately: a
  /// server-scoped sign-out would try to revoke a session for a user that, by
  /// this point, no longer exists.
  Future<void> deleteAccount() async {
    final appleCode = await _appleCodeForRevocation();
    await _client.functions.invoke(
      'delete-account',
      body: appleCode == null ? null : {'apple_authorization_code': appleCode},
    );
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (error, stack) {
      // The account is already gone — the one thing that mattered already
      // succeeded. A local sign-out hiccup here must not read as the
      // deletion having failed.
      AppLogger.warn(
        _deletionTag,
        'local sign-out after deleteAccount failed',
        error,
        stack,
      );
    }
  }

  /// Whether the signed-in account has an Apple identity, and so whether
  /// deleting it means revoking an Apple token as well.
  ///
  /// `app_metadata.providers` is the one Supabase keeps current as identities
  /// are linked; the identities list is checked too, for a session restored
  /// from before a link was made.
  bool get isAppleAccount {
    final user = currentUser;
    if (user == null) return false;
    final providers = user.appMetadata['providers'];
    if (providers is List && providers.contains('apple')) return true;
    return user.identities?.any((identity) => identity.provider == 'apple') ??
        false;
  }

  /// One fresh Apple authorization code for the `delete-account` function to
  /// revoke this app's Apple token with — or null when there is nothing to
  /// revoke, or no way to ask.
  ///
  /// Apple requires an app offering Sign in with Apple to revoke the member's
  /// token when they delete their account (Guideline 5.1.1(v)). Revocation
  /// takes a refresh or access token, and native sign-in never produces one
  /// anywhere this app can reach: the app hands Supabase the identity token
  /// only. So the member confirms with Apple once more, here, and the function
  /// trades the code for a token and revokes it straight away. Nothing is
  /// stored anywhere, and a retry simply asks again — a code is single-use.
  ///
  /// Dismissing Apple's sheet cancels the deletion: [AuthCancelled], and
  /// nothing has been touched. Any other failure still deletes the account,
  /// without revoking, and says so loudly in the log — the member asked to
  /// leave, and Apple's sheet misbehaving is not a reason to keep them. They
  /// can remove the app under Settings → Apple ID → Sign in with Apple.
  Future<String?> _appleCodeForRevocation() async {
    if (!isAppleAccount) return null;
    if (!offersAppleSignIn) {
      AppLogger.error(
        _deletionTag,
        'Apple account deleting from a device that cannot show Apple\'s '
        'sheet — deleting WITHOUT revoking the Apple token',
      );
      return null;
    }
    AppLogger.info(
      _deletionTag,
      'Apple account — asking Apple for a code to revoke with -> calling',
    );
    try {
      final credential = await _requestAppleCredential(scopes: const []);
      AppLogger.info(_deletionTag, 'Apple authorization code <- present');
      return credential.authorizationCode;
    } on SignInWithAppleAuthorizationException catch (error, stack) {
      if (error.code == AuthorizationErrorCode.canceled) {
        AppLogger.info(
          _deletionTag,
          'Apple sheet dismissed — deletion cancelled, nothing touched',
        );
        throw const AuthCancelled();
      }
      AppLogger.error(
        _deletionTag,
        'Apple re-authorisation FAILED (code.name="${error.code.name}") — '
        'deleting WITHOUT revoking the Apple token',
        error,
        stack,
      );
      return null;
    } catch (error, stack) {
      AppLogger.error(
        _deletionTag,
        'Apple re-authorisation FAILED with ${error.runtimeType} — deleting '
        'WITHOUT revoking the Apple token',
        error,
        stack,
      );
      return null;
    }
  }

  /// The signed-in member's own data, as one JSON object, via the
  /// `export-data` Edge Function. Offered alongside deletion so someone has a
  /// copy before they choose to lose it.
  Future<Map<String, dynamic>> exportData() async {
    final response = await _client.functions.invoke('export-data');
    return Map<String, dynamic>.from(response.data as Map);
  }

  // -------------------------------------------------------------- google ---

  /// The tag every line of the Google flow is logged under. Grep for this.
  static const _tag = 'GoogleAuth';

  // v7's GoogleSignIn.instance must be initialized exactly once. Memoised so
  // repeated sign-in taps don't re-init.
  Future<void>? _googleInit;

  Future<void> _ensureGoogleInitialized() {
    if (_googleInit != null) {
      // Say so explicitly: otherwise stage 2/6 simply vanishes from the log on
      // the second tap and reads like a skipped step.
      AppLogger.info(_tag, '2/6 initialize() — already done (memoised)');
      return _googleInit!;
    }
    return _googleInit = _initializeGoogle();
  }

  Future<void> _initializeGoogle() async {
    AppLogger.info(_tag, '2/6 initialize() -> calling');
    try {
      await GoogleSignIn.instance.initialize(
        // iOS uses clientId; Android uses serverClientId (the Web client ID).
        // Empty → null so the SDK falls back to its platform config file.
        //
        // The platform guard is a correctness fix, not a bug fix: until now the
        // iOS client ID was passed on every platform. It is **not** the cause
        // of the Play Store failure, and must not be recorded as its
        // resolution — `google_sign_in_android` discards `clientId` before it
        // reaches the native layer ("not supported on Android"), and
        // `GoogleSignInPlugin.java` reads only `getServerClientId()`. Passing
        // it did nothing; not passing it does nothing. It is corrected because
        // code that contradicts the comment above it is a trap for whoever
        // reads this next.
        //
        // [kIsWeb] first because [defaultTargetPlatform] reports the browser's
        // host OS on web, where iOS would be the wrong answer.
        clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            ? (AppConfig.googleIosClientId.isEmpty
                  ? null
                  : AppConfig.googleIosClientId)
            : null,
        serverClientId: AppConfig.googleWebClientId.isEmpty
            ? null
            : AppConfig.googleWebClientId,
      );
      AppLogger.info(_tag, '2/6 initialize() <- returned ok');
    } catch (error, stack) {
      AppLogger.error(
        _tag,
        '2/6 initialize() FAILED with ${error.runtimeType}',
        error,
        stack,
      );
      rethrow;
    }
  }

  /// Native Google sign-in (google_sign_in v7), exchanged for a Supabase
  /// session via the ID token.
  ///
  /// v7 splits authentication from authorization: [GoogleSignIn.authenticate]
  /// yields the account and its ID token; the access token comes separately
  /// from the account's [GoogleSignInAuthorizationClient]. On Android this
  /// drives the system Credential Manager sheet.
  ///
  /// Every stage announces itself under `[GoogleAuth]`, numbered `n/6`, before
  /// and after the call it wraps. The numbering is the diagnostic: where the
  /// log stops is where execution stopped. If the last line is
  /// `3/6 authenticate() -> calling` and nothing follows, the failure is inside
  /// the native Credential Manager call and will only be visible in
  /// `adb logcat`, not here.
  Future<AuthResponse> signInWithGoogle() async {
    AppLogger.info(_tag, '===== signInWithGoogle() begin =====');
    try {
      final response = await _signInWithGoogle();
      AppLogger.info(_tag, '===== signInWithGoogle() complete =====');
      return response;
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } catch (error, stack) {
      // Nothing typed matched. This is the branch that used to lose the error
      // entirely, so it is the loudest.
      AppLogger.error(_tag, '[UNHANDLED] ${error.runtimeType}', error, stack);
      throw AuthFailure(
        'Google sign-in didn\'t go through. Try again.',
        code: 'unhandled:${error.runtimeType}',
        details: '$error',
        stackTrace: stack,
      );
    }
  }

  Future<AuthResponse> _signInWithGoogle() async {
    final signIn = GoogleSignIn.instance;

    // --- 1/6 config -------------------------------------------------------
    _logConfigSelfCheck();

    // --- 2/6 initialize ---------------------------------------------------
    await _ensureGoogleInitialized();

    // Native sign-in isn't offered on every platform (notably web, where v7
    // wants renderButton instead). Scoped to mobile this phase.
    if (!signIn.supportsAuthenticate()) {
      AppLogger.error(_tag, 'supportsAuthenticate() is false on this platform');
      throw const AuthFailure(
        'Google sign-in isn\'t available on this device.',
        code: 'unsupportedPlatform',
      );
    }

    // --- 3/6 authenticate -------------------------------------------------
    // The stage the crash log points at: on Android this hands off to the
    // system Credential Manager sheet, which is when MainActivity loses
    // visibility.
    final GoogleSignInAccount account;
    AppLogger.info(
      _tag,
      '3/6 authenticate() -> calling '
      '(native Credential Manager takes the foreground here)',
    );
    try {
      // v7: authenticate() THROWS on cancel/failure — it never returns null.
      account = await signIn.authenticate();
      AppLogger.info(_tag, '3/6 authenticate() <- returned an account');
    } on GoogleSignInException catch (error, stack) {
      throw _mapGoogleException(error, stack, stage: '3/6 authenticate');
    } catch (error, stack) {
      AppLogger.error(
        _tag,
        '3/6 authenticate() FAILED with non-Google ${error.runtimeType}',
        error,
        stack,
      );
      rethrow;
    }

    // --- 4/6 authorize scopes ---------------------------------------------
    const scopes = <String>['email', 'profile'];
    final GoogleSignInClientAuthorization authorization;
    AppLogger.info(_tag, '4/6 authorizeScopes($scopes) -> calling');
    try {
      authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      AppLogger.info(
        _tag,
        '4/6 authorizeScopes <- access token '
        '${authorization.accessToken.isEmpty ? 'ABSENT' : 'present'}',
      );
    } on GoogleSignInException catch (error, stack) {
      throw _mapGoogleException(error, stack, stage: '4/6 authorizeScopes');
    }

    // --- 5/6 id token -----------------------------------------------------
    // Presence only. The token itself is a credential and is never logged.
    final idToken = account.authentication.idToken;
    AppLogger.info(
      _tag,
      '5/6 idToken <- '
      '${idToken == null ? 'ABSENT' : 'present (${idToken.length} chars)'}',
    );
    if (idToken == null) {
      AppLogger.error(_tag, '5/6 idToken FAILED — Google returned no ID token');
      throw const AuthFailure(
        'Google sign-in isn\'t available right now.',
        code: 'missingIdToken',
        details:
            'authenticate() succeeded but returned no idToken. On Android that '
            'points at serverClientId not being accepted by the native SDK.',
      );
    }

    // --- 6/6 supabase -----------------------------------------------------
    AppLogger.info(_tag, '6/6 signInWithIdToken() -> calling Supabase');
    try {
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
      AppLogger.info(
        _tag,
        '6/6 signInWithIdToken() <- session '
        '${response.session == null ? 'ABSENT' : 'established'}',
      );
      return response;
    } on AuthException catch (error, stack) {
      // Reaching Supabase but being rejected almost always means the token's
      // audience isn't trusted: the Web client ID is missing from the Supabase
      // provider's Authorized Client IDs, or serverClientId wasn't passed. A
      // developer misconfiguration, not a user problem — log it loudly.
      AppLogger.error(
        _tag,
        '6/6 signInWithIdToken() FAILED — AuthException '
        'status=${error.statusCode} code=${error.code}: ${error.message}',
        error,
        stack,
      );
      AppLogger.error(
        _tag,
        '[CONFIG] Supabase rejected the Google ID token, so the native half '
        'worked. Check Supabase → Auth → Providers → Google → Authorized '
        'Client IDs contains the Web (and iOS) client ID.',
      );
      throw AuthFailure(
        'Google sign-in isn\'t available right now.',
        code: 'supabase:${error.code ?? error.statusCode ?? 'authError'}',
        details: 'AuthException(${error.statusCode}): ${error.message}',
        stackTrace: stack,
      );
    }
  }

  /// Stage 1/6 — reports whether the compile-time config actually reached the
  /// app, in masked form.
  ///
  /// An empty `serverClientId` is the most common cause of a Google sign-in
  /// that dies without a message on Android, and it costs one log line to rule
  /// out. Values are never printed — only presence and a six-character tail,
  /// which is enough to tell two client IDs apart without disclosing either.
  void _logConfigSelfCheck() {
    final web = AppConfig.googleWebClientId;
    final ios = AppConfig.googleIosClientId;

    AppLogger.info(_tag, '1/6 config check');
    AppLogger.info(
      _tag,
      '  webClientId (Android serverClientId): ${_maskClientId(web)}',
    );
    AppLogger.info(_tag, '  iosClientId (iOS clientId): ${_maskClientId(ios)}');
    AppLogger.info(
      _tag,
      '  serverClientId passed to initialize: ${web.isEmpty ? 'no' : 'yes'}',
    );
    AppLogger.info(_tag, '  supabase host: ${_supabaseHost()}');

    if (web.isEmpty) {
      AppLogger.error(
        _tag,
        '[CONFIG] serverClientId is EMPTY — Android sign-in will fail with '
        'clientConfigurationError. Check GOOGLE_WEB_CLIENT_ID in env.json and '
        'that the app was launched with --dart-define-from-file=env.json.',
      );
    } else if (!web.endsWith('.apps.googleusercontent.com')) {
      AppLogger.warn(
        _tag,
        '[CONFIG] webClientId does not end in .apps.googleusercontent.com — '
        'is that really the Web OAuth client ID?',
      );
    }
  }

  /// Masks a Google client ID so the log can still tell two of them apart.
  ///
  /// A plain six-character tail is worthless here — every client ID ends
  /// `...googleusercontent.com`, so masking the raw value prints `…nt.com` for
  /// all of them. Drop the shared suffix first, then mask what's actually
  /// distinguishing: the tail of the ID itself.
  String _maskClientId(String value) {
    const suffix = '.apps.googleusercontent.com';
    final id = value.endsWith(suffix)
        ? value.substring(0, value.length - suffix.length)
        : value;
    return AppLogger.mask(id);
  }

  String _supabaseHost() {
    final url = AppConfig.supabaseUrl;
    if (url.isEmpty) return 'EMPTY';
    return Uri.tryParse(url)?.host ?? 'unparseable';
  }

  /// Maps Credential Manager's deliberately-vague failures to either a silent
  /// cancel or user-facing copy, always logging the raw exception first — these
  /// codes collapse several distinct conditions (dismiss, no account, misconfig)
  /// into lookalikes, so the description and details matter as much as the code.
  ///
  /// Switches on `code.name` rather than the enum: `GoogleSignInExceptionCode`
  /// has had export problems across v7 patch releases, and is documented as
  /// gaining new values without a breaking change. A string switch with a
  /// default survives both.
  Exception _mapGoogleException(
    GoogleSignInException error,
    StackTrace stack, {
    required String stage,
  }) {
    final code = error.code.name;
    final nested = error.details;
    // Every field the native exception actually carries — not just the two
    // (`code`, `description`) the old copy of this method surfaced. `nested`
    // is `Object?`: on Android it is sometimes itself a wrapped
    // exception/error rather than a string, so its own runtimeType travels
    // too rather than only whatever its toString() happens to produce. This
    // whole string is what reaches AuthFailure.details, and from there
    // "Copy details" — if it's genuinely empty, that says so explicitly
    // instead of leaving a bare, unexplained `details=null`.
    final details =
        'type=${error.runtimeType}\n'
        'code=$code\n'
        'description=${error.description ?? '(none)'}\n'
        'details=${nested == null ? '(none)' : '$nested (${nested.runtimeType})'}';

    AppLogger.error(
      _tag,
      '$stage FAILED — GoogleSignInException code.name="$code"',
      error,
      stack,
    );
    // The composed payload above — not just the exception's own toString() —
    // is what "Copy details" shows. Log it explicitly, under the same tag,
    // before any mapping to user-facing copy happens below, so adb logcat
    // carries exactly what the screen will.
    AppLogger.error(_tag, '$stage raw payload:\n$details');

    switch (code) {
      // Dismissed the sheet. Not an error, and the only quiet path.
      case 'canceled':
        AppLogger.info(_tag, '$stage — user cancelled; returning quietly');
        return const AuthCancelled();

      // Not a dismissal — something cut the flow short. Previously folded in
      // with cancel, which is precisely how a real failure went unseen.
      case 'interrupted':
        return AuthFailure(
          'Sign-in was interrupted before it finished. Try again.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      // The client IDs aren't reaching the native SDK.
      case 'clientConfigurationError':
        AppLogger.error(
          _tag,
          '[CONFIG] The native SDK rejected the client configuration. Check '
          'GOOGLE_WEB_CLIENT_ID reaches initialize(serverClientId:). If the '
          'description mentions google-services.json, ignore it — this project '
          'is Supabase, not Firebase.',
        );
        return AuthFailure(
          'Google sign-in isn\'t set up correctly in this build.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      // Credential Manager had nothing to hand back. This code alone is
      // ambiguous — see [_mapUnknownError].
      case 'unknownError':
        return _mapUnknownError(error, code: code, details: details, stack: stack);

      // Play Services or the credential UI isn't usable here.
      case 'providerConfigurationError':
      case 'uiUnavailable':
        return AuthFailure(
          'Google sign-in isn\'t available on this device. It needs Google '
          'Play services.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      case 'userMismatch':
        return AuthFailure(
          'That account doesn\'t match the one signed in on this device. Sign '
          'it out, then try again.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      // A code added in a later v7 patch. Report it rather than guess at it.
      default:
        AppLogger.error(_tag, '[UNMAPPED] unrecognised code.name="$code"');
        return AuthFailure(
          'Google sign-in isn\'t available right now.',
          code: code,
          details: details,
          stackTrace: stack,
        );
    }
  }

  /// The four things worth checking, in the order they're most likely wrong
  /// for a rebuilt-from-scratch dev machine — see `docs/new_machine_setup.md`.
  /// Debug-only copy: none of this belongs in front of someone who isn't the
  /// maintainer, and in release the friendly message plus [AuthFailure.details]
  /// (still the raw `code=…\ndescription=…` text) is all that ships.
  static const _devConsoleChecklist =
      '1. GOOGLE_WEB_CLIENT_ID is the Web client ID, not the Android one.\n'
      '2. The signing-in Google account is a Test user, if the OAuth consent '
      'screen is in Testing.\n'
      '3. Supabase → Auth → Providers → Google → Authorized Client IDs '
      'contains that Web client ID.\n'
      '4. The package name and SHA-1 are registered on an Android OAuth '
      'client.';

  /// `unknownError` is Credential Manager's catch-all for "nothing to hand
  /// back", and it is the same code whether the cause is a device with no
  /// Google account or a dashboard that was never finished. [error.description]
  /// is the only thing that can tell the two apart — a `[28444]` /
  /// "Developer console is not set up correctly" description names the
  /// dashboard fault outright; a description naming missing accounts or
  /// credentials names the device instead. When the description says neither,
  /// this can't honestly claim to know which one it is, so it says both and
  /// names the likelier cause rather than guessing.
  Exception _mapUnknownError(
    GoogleSignInException error, {
    required String code,
    required String details,
    required StackTrace stack,
  }) {
    final description = (error.description ?? '').toLowerCase();
    final looksLikeDevConsole =
        description.contains('28444') ||
        description.contains('developer console');
    final looksLikeNoAccount =
        !looksLikeDevConsole &&
        (description.contains('no accounts') ||
            description.contains('no credentials available') ||
            description.contains('add a google account'));

    if (looksLikeDevConsole) {
      AppLogger.error(
        _tag,
        '[CONFIG] Developer console is not set up correctly. Check, in '
        'order:\n$_devConsoleChecklist',
      );
      return AuthFailure(
        kDebugMode
            ? 'Google sign-in isn\'t set up correctly in this build. Check, '
                  'in order:\n$_devConsoleChecklist'
            : 'Google sign-in isn\'t available right now.',
        code: code,
        details: details,
        stackTrace: stack,
      );
    }

    if (looksLikeNoAccount) {
      AppLogger.error(
        _tag,
        '[CONFIG] Credential Manager reports no account on this device.',
      );
      return AuthFailure(
        'Google couldn\'t find an account on this device. Add a Google '
        'account, then try again.',
        code: code,
        details: details,
        stackTrace: stack,
      );
    }

    // The description didn't say which. Both are real possibilities; a
    // rebuilt dev machine makes the console the likelier one, but this must
    // not present a guess as a fact.
    AppLogger.error(
      _tag,
      '[CONFIG] "No credential available" and the description does not say '
      'why. Likeliest is the developer console, not the device — check, in '
      'order:\n$_devConsoleChecklist\nOtherwise, check a Google account is '
      'signed in on this device.',
    );
    return AuthFailure(
      kDebugMode
          ? 'Google couldn\'t sign you in. Likeliest cause is the console, '
                'not the device — check, in order:\n$_devConsoleChecklist\n'
                'Otherwise, add a Google account on this device.'
          : 'Google couldn\'t sign you in. Check a Google account is added '
                'on this device, then try again.',
      code: code,
      details: details,
      stackTrace: stack,
    );
  }

  // --------------------------------------------------------------- apple ---

  /// The tag every line of the Apple flow is logged under. Grep for this.
  static const _appleTag = 'AppleAuth';

  /// Whether this build offers Sign in with Apple at all: iOS only.
  ///
  /// App Store Guideline 4.8 is an App Store rule, so it is met where the App
  /// Store is. Android keeps Google and email/password — the web-based Apple
  /// flow it would need (a Services ID and a return URL) is not configured,
  /// and a button that opened a broken browser tab would be worse than none.
  /// [kIsWeb] first, for the same reason as the Google client ID above.
  static bool get offersAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Native Sign in with Apple, exchanged for a Supabase session via the
  /// identity token — the same shape as [signInWithGoogle]: the platform hands
  /// over an ID token, and Supabase verifies it.
  ///
  /// Every stage announces itself under `[AppleAuth]`, numbered `n/6`, before
  /// and after the call it wraps. If the last line is
  /// `3/6 getAppleIDCredential() -> calling` and nothing follows, the failure
  /// is inside Apple's own sheet and will only be visible in the device
  /// console, not here.
  Future<AuthResponse> signInWithApple() async {
    AppLogger.info(_appleTag, '===== signInWithApple() begin =====');
    try {
      final response = await _signInWithApple();
      AppLogger.info(_appleTag, '===== signInWithApple() complete =====');
      return response;
    } on AuthCancelled {
      rethrow;
    } on AuthFailure {
      rethrow;
    } catch (error, stack) {
      AppLogger.error(
        _appleTag,
        '[UNHANDLED] ${error.runtimeType}',
        error,
        stack,
      );
      throw AuthFailure(
        'Apple sign-in didn\'t go through. Try again.',
        code: 'unhandled:${error.runtimeType}',
        details: '$error',
        stackTrace: stack,
      );
    }
  }

  Future<AuthResponse> _signInWithApple() async {
    // --- 1/6 platform -----------------------------------------------------
    if (!offersAppleSignIn) {
      AppLogger.error(_appleTag, '1/6 platform — not iOS; Apple not offered');
      throw const AuthFailure(
        'Sign in with Apple is only available on iPhone.',
        code: 'unsupportedPlatform',
      );
    }
    AppLogger.info(_appleTag, '1/6 platform — iOS');

    // --- 2/6 nonce --------------------------------------------------------
    // Raw to Supabase, hashed to Apple — see AppleNonce for why the
    // direction matters. Neither value is logged.
    final nonce = AppleNonce.generate();
    AppLogger.info(
      _appleTag,
      '2/6 nonce — generated (SHA-256 to Apple, raw to Supabase)',
    );

    // --- 3/6 credential ---------------------------------------------------
    final AuthorizationCredentialAppleID credential;
    AppLogger.info(
      _appleTag,
      '3/6 getAppleIDCredential() -> calling '
      '(Apple\'s sheet takes the foreground here)',
    );
    try {
      credential = await _requestAppleCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce.hashed,
      );
      AppLogger.info(
        _appleTag,
        '3/6 getAppleIDCredential() <- returned a credential (name '
        '${appleFullName(credential.givenName, credential.familyName) == null ? 'absent' : 'present — first authorisation'})',
      );
    } on SignInWithAppleException catch (error, stack) {
      throw _mapAppleException(error, stack, stage: '3/6 getAppleIDCredential');
    }

    // --- 4/6 identity token -----------------------------------------------
    // Presence only. The token itself is a credential and is never logged.
    final idToken = credential.identityToken;
    AppLogger.info(
      _appleTag,
      '4/6 identityToken <- '
      '${idToken == null ? 'ABSENT' : 'present (${idToken.length} chars)'}',
    );
    if (idToken == null) {
      AppLogger.error(
        _appleTag,
        '4/6 identityToken FAILED — Apple returned no identity token',
      );
      throw const AuthFailure(
        'Apple sign-in isn\'t available right now.',
        code: 'missingIdToken',
        details:
            'getAppleIDCredential() succeeded but returned no identityToken.',
      );
    }

    // --- 5/6 supabase -----------------------------------------------------
    final AuthResponse response;
    AppLogger.info(_appleTag, '5/6 signInWithIdToken() -> calling Supabase');
    try {
      response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: nonce.raw,
      );
      AppLogger.info(
        _appleTag,
        '5/6 signInWithIdToken() <- session '
        '${response.session == null ? 'ABSENT' : 'established'}',
      );
    } on AuthException catch (error, stack) {
      AppLogger.error(
        _appleTag,
        '5/6 signInWithIdToken() FAILED — AuthException '
        'status=${error.statusCode} code=${error.code}: ${error.message}',
        error,
        stack,
      );
      // Reaching Supabase and being turned away means the native half worked.
      // Either the Apple provider isn't set up to trust this app's tokens, or
      // the nonce pair was crossed — and Supabase says only "nonce", so name
      // where to look.
      AppLogger.error(
        _appleTag,
        '[CONFIG] Supabase rejected the Apple identity token, so the native '
        'half worked. Check Supabase → Auth → Providers → Apple is enabled '
        'and its Client IDs include the bundle ID '
        'com.calledpresentations.prayerwalk. A message about the nonce means '
        'the raw/hashed pair was crossed — see AppleNonce.',
      );
      throw AuthFailure(
        'Apple sign-in isn\'t available right now.',
        code: 'supabase:${error.code ?? error.statusCode ?? 'authError'}',
        details: 'AuthException(${error.statusCode}): ${error.message}',
        stackTrace: stack,
      );
    }

    // --- 6/6 name ---------------------------------------------------------
    await _keepFirstAppleName(response.user, credential);
    return response;
  }

  /// Stage 6/6 — the person's name, which Apple sends exactly once.
  ///
  /// Apple includes `givenName` / `familyName` only on the *first*
  /// authorisation between an Apple ID and this app — never on a later
  /// sign-in, and not after a reinstall either. Nor is the name in the
  /// identity token, so the new-user trigger that names a Google or email
  /// account from its metadata has nothing to read: the profile row starts
  /// with an empty `full_name`. If it isn't written now, it never can be.
  ///
  /// Written only over an empty name (`''` is what the trigger stores when it
  /// has none). Apple does send the name again after a member removes the app
  /// under Settings → Apple ID → Sign in with Apple, and by then they may have
  /// chosen a display name of their own here; this must not overwrite it.
  ///
  /// A failure is logged and swallowed. The session is already real, and
  /// failing the sign-in would not bring the name back — Apple won't send it
  /// to a retry. The member shows as "Walker" until they set a name on Edit
  /// profile.
  Future<void> _keepFirstAppleName(
    User? user,
    AuthorizationCredentialAppleID credential,
  ) async {
    final name = appleFullName(credential.givenName, credential.familyName);
    if (name == null) {
      AppLogger.info(
        _appleTag,
        '6/6 name — none sent (normal after the first authorisation); '
        'profile left as it is',
      );
      return;
    }
    if (user == null) {
      AppLogger.error(_appleTag, '6/6 name — no user on the session; NOT saved');
      return;
    }
    for (var attempt = 1; ; attempt++) {
      AppLogger.info(
        _appleTag,
        '6/6 name -> writing into an empty profile name (attempt $attempt/3)',
      );
      try {
        await _client
            .from('profiles')
            .update({'full_name': name})
            .eq('id', user.id)
            .eq('full_name', '');
        AppLogger.info(_appleTag, '6/6 name <- done');
        return;
      } catch (error, stack) {
        if (attempt >= 3) {
          AppLogger.error(
            _appleTag,
            '6/6 name FAILED — Apple will not send it again; this member '
            'shows as "Walker" until they set a name on Edit profile',
            error,
            stack,
          );
          return;
        }
        AppLogger.warn(_appleTag, '6/6 name write failed; retrying', error);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  /// The name Apple sent, as one display name — or null when it sent none.
  ///
  /// Either half may be missing or blank: the person can edit both on Apple's
  /// sheet, including clearing them. Clamped to the same length the Edit
  /// profile form allows.
  static String? appleFullName(String? givenName, String? familyName) {
    final parts = [
      givenName,
      familyName,
    ].map((part) => part?.trim() ?? '').where((part) => part.isNotEmpty);
    if (parts.isEmpty) return null;
    return clampField(parts.join(' '), ProfileLimits.displayName);
  }

  /// Maps Apple's sheet failures to either a silent cancel or user-facing
  /// copy, always logging the raw exception first — in the same order, and
  /// for the same reason, as [_mapGoogleException].
  ///
  /// Switches on `code.name` with a default, as the Google mapper does:
  /// `AuthorizationErrorCode` has already grown values for passkey flows this
  /// app never starts.
  Exception _mapAppleException(
    SignInWithAppleException error,
    StackTrace stack, {
    required String stage,
  }) {
    final code = error is SignInWithAppleAuthorizationException
        ? error.code.name
        : error.runtimeType.toString();
    final details = 'type=${error.runtimeType}\ncode=$code\n$error';

    AppLogger.error(
      _appleTag,
      '$stage FAILED — ${error.runtimeType} code="$code"',
      error,
      stack,
    );
    AppLogger.error(_appleTag, '$stage raw payload:\n$details');

    switch (code) {
      // Dismissed the sheet. Not an error, and the only quiet path.
      case 'canceled':
        AppLogger.info(_appleTag, '$stage — user cancelled; returning quietly');
        return const AuthCancelled();

      case 'failed':
      case 'invalidResponse':
        return AuthFailure(
          'Apple sign-in didn\'t go through. Try again.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      // Apple's sheet couldn't be shown or couldn't finish on its own terms.
      case 'notHandled':
      case 'notInteractive':
        return AuthFailure(
          'Apple sign-in isn\'t available on this device right now.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      // iOS's catch-all (ASAuthorizationError 1000). It is what a device with
      // no Apple ID signed in returns — and also what every attempt returns
      // when the build is missing the Sign in with Apple entitlement. The
      // description doesn't say which, so the log names both.
      case 'unknown':
        AppLogger.error(
          _appleTag,
          '[CONFIG] Apple returned "unknown" (1000). If this happens on '
          'every attempt, check the build carries the '
          'com.apple.developer.applesignin entitlement and its provisioning '
          'profile has the Sign In with Apple capability. Otherwise, check an '
          'Apple ID is signed in on this device.',
        );
        return AuthFailure(
          'Apple couldn\'t sign you in. Check this iPhone is signed in to an '
          'Apple ID in Settings, then try again.',
          code: code,
          details: details,
          stackTrace: stack,
        );

      case 'SignInWithAppleNotSupportedException':
        return AuthFailure(
          'Sign in with Apple needs a newer version of iOS.',
          code: 'notSupported',
          details: details,
          stackTrace: stack,
        );

      // A credentials error, a code from a later release, or a platform
      // exception the plugin couldn't name. Report it rather than guess.
      default:
        AppLogger.error(_appleTag, '[UNMAPPED] unrecognised code="$code"');
        return AuthFailure(
          'Apple sign-in isn\'t available right now.',
          code: code,
          details: details,
          stackTrace: stack,
        );
    }
  }

  String _emailMessage(AuthException error) {
    final code = error.code;
    if (code == 'invalid_credentials' ||
        error.message.toLowerCase().contains('invalid login')) {
      return 'That email and password don\'t match. Check them and try again.';
    }
    if (code == 'user_already_exists' || code == 'email_exists') {
      return 'There\'s already an account for that email. Try signing in.';
    }
    if (code == 'weak_password') {
      return 'Choose a longer password — at least 6 characters.';
    }
    if (code == 'email_not_confirmed') {
      return 'Confirm your email first — check your inbox for the link.';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return 'Too many attempts just now. Wait a moment, then try again.';
    }
    return error.message;
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
