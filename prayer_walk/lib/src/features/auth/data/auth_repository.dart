import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/profile.dart';

/// A sign-in problem worth showing the person, phrased in the app's voice.
///
/// Anything the repository throws as an [AuthFailure] is safe — and intended —
/// to display inline on the auth screen.
///
/// [code] and [details] are the diagnostic half: the machine-readable cause
/// (e.g. `unknownError`) and the raw exception text. They let the screen show
/// what actually failed, and let it be copied off the device, without putting
/// SDK vocabulary into [message].
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code, this.details, this.stackTrace});

  final String message;
  final String? code;
  final String? details;
  final StackTrace? stackTrace;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// A deliberate cancellation — the person dismissed the Google sheet.
///
/// This is not an error. The screen catches it and quietly returns to the login
/// form: no toast, no spinner left spinning. It exists as its own type so a
/// dismiss is never mistaken for a failure worth reporting.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// All authentication against Supabase, plus native Google via google_sign_in
/// v7. The rest of the app talks to this, never to the SDK directly.
class AuthRepository {
  AuthRepository();

  // ------------------------------------------------------------- session ---

  /// Supabase auth events — `initialSession`, `signedIn`, `signedOut`, token
  /// refreshes. `supabase_flutter` persists and restores the session itself, so
  /// this replays the restored session to new listeners on launch.
  Stream<AuthState> authStateChanges() => supabase.auth.onAuthStateChange;

  Session? get currentSession => supabase.auth.currentSession;

  User? get currentUser => supabase.auth.currentUser;

  // --------------------------------------------------------------- email ---

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await supabase.auth.signInWithPassword(
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
      final response = await supabase.auth.signUp(
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
      final row = await supabase
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

  Future<void> signOut() => supabase.auth.signOut();

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
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
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
      AppLogger.error(
        _tag,
        '[UNHANDLED] ${error.runtimeType}: $error',
        error,
        stack,
      );
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
      final response = await supabase.auth.signInWithIdToken(
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
    final details =
        'code=$code\ndescription=${error.description}\ndetails=${error.details}';

    AppLogger.error(
      _tag,
      '$stage FAILED — GoogleSignInException code.name="$code" :: $error',
      error,
      stack,
    );

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

      // Credential Manager had nothing to hand back. Two common causes on an
      // emulator: no Google account added, or this build's signing SHA-1 isn't
      // registered on the Android OAuth client.
      case 'unknownError':
        AppLogger.error(
          _tag,
          '[CONFIG] "No credential available" here means either no Google '
          'account is signed in on this device, or the debug SHA-1 for '
          'com.calledpresentations.prayer_walk is not registered on the '
          'Android OAuth client. Run: gradlew signingReport',
        );
        return AuthFailure(
          'Google couldn\'t sign you in. Check a Google account is added on '
          'this device, then try again.',
          code: code,
          details: details,
          stackTrace: stack,
        );

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
