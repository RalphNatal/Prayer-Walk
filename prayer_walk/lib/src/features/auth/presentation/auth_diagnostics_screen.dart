import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, OAuthProvider;

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/auth_diagnostics_verdict.dart';
import '../domain/google_config_diagnostics.dart';
import '../domain/google_id_token.dart';

const _tag = 'AuthDiag';

/// Reads exactly the same `android/app/build.gradle.kts` and
/// `AndroidManifest.xml` `applicationId` this app ships with — kept here as a
/// literal because the diagnostic has to compare against *something*, and the
/// only honest source is the value Gradle is actually configured with.
const _expectedApplicationId = 'com.calledpresentations.prayer_walk';

const _adbClearCommand =
    r'& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -c';
const _adbFilterCommand =
    r'& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat | '
    r'Select-String -Pattern "CredMan|Credential|GoogleSign|28444"';

const _googleProbeScopes = <String>['email', 'profile'];

/// Which link in the Google sign-in chain is broken, read straight from the
/// running build — and, for the two rows that matter most, straight from a
/// live attempt rather than a guess about what a live attempt would do.
///
/// `28444` ("Developer console is not set up correctly") collapses four
/// distinct dashboard-side faults into one Credential Manager error code —
/// see `AuthRepository._mapGoogleException`. Nothing in this app can fix any
/// of them; what it can do is stop making someone guess which one it is.
///
/// The static rows (config presence and shape, package name) are read from
/// this build directly and need no action. **Run all** additionally attempts
/// the real thing: `GoogleSignIn.instance.authenticate()` in isolation, a
/// decode of the resulting ID token's `aud` claim, and — only if that
/// audience matches [AppConfig.googleWebClientId] — a real
/// `signInWithIdToken` against Supabase. That last step is a genuine sign-in
/// attempt: if it succeeds, the session it creates is real. That is
/// deliberate — it is the only way to tell "Google refused" apart from
/// "Google issued a token and Supabase rejected it" with evidence instead of
/// a guess, and if it succeeds, sign-in is no longer broken.
///
/// **Reachable with no session.** This screen exists for when sign-in itself
/// is what's broken, so it cannot be gated behind signing in: it has its own
/// debug-only top-level route (see `Routes.authDiagnosticsPath` and the
/// router's redirect), a link on `AuthScreen` itself, a "Run diagnostics"
/// action on the sign-in failure dialog, and — for a maintainer who is
/// already signed in on another account — the existing entry under
/// Settings → Diagnostics.
///
/// **Debug builds only**, gated the same way `ScriptureDiagnostics` is: the
/// route is only ever registered in debug, and this widget's own `build`
/// refuses to render anything in release as a second line of defence.
class AuthDiagnosticsScreen extends StatefulWidget {
  const AuthDiagnosticsScreen({super.key});

  @override
  State<AuthDiagnosticsScreen> createState() => _AuthDiagnosticsScreenState();
}

class _AuthDiagnosticsScreenState extends State<AuthDiagnosticsScreen> {
  PackageInfo? _packageInfo;
  bool _running = false;

  _Check _supabaseHealthCheck = const _Check.unknown();
  _Check _googleProbeCheck = const _Check.unknown();
  _Check _audCheck = const _Check.unknown('run the Google token probe first');
  _Check _supabaseAcceptCheck = const _Check.unknown(
    'run the Google token probe first',
  );

  GoogleProbeOutcome _probeOutcome = GoogleProbeOutcome.notRun;
  String? _refusalCode;
  String? _refusalReason;
  bool? _audMatches;
  SupabaseAcceptOutcome _supabaseOutcome = SupabaseAcceptOutcome.notRun;
  String? _observedAud;
  String _rawGoogleException = '';

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  // ------------------------------------------------------------ run all ---

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _supabaseHealthCheck = const _Check.checking();
      _googleProbeCheck = const _Check.checking();
      _audCheck = const _Check.unknown('waiting on the Google token probe');
      _supabaseAcceptCheck = const _Check.unknown(
        'waiting on the Google token probe',
      );
      _probeOutcome = GoogleProbeOutcome.notRun;
      _refusalCode = null;
      _refusalReason = null;
      _audMatches = null;
      _supabaseOutcome = SupabaseAcceptOutcome.notRun;
      _observedAud = null;
      _rawGoogleException = '';
    });

    // Independent probes — the Supabase health check doesn't need to wait on
    // the Google native sheet, or vice versa.
    await Future.wait([_checkSupabaseHealth(), _probeGoogleToken()]);

    if (mounted) setState(() => _running = false);
  }

  Future<void> _checkSupabaseHealth() async {
    final result = await _probeSupabaseHealth();
    if (mounted) setState(() => _supabaseHealthCheck = result);
  }

  /// An unauthenticated GoTrue health check — proves the URL resolves to a
  /// real Supabase project and the key is at least well-formed enough to be
  /// accepted as an `apikey` header, without needing a signed-in session.
  Future<_Check> _probeSupabaseHealth() async {
    final url = AppConfig.supabaseUrl;
    final key = AppConfig.supabasePublishableKey;
    if (url.isEmpty || key.isEmpty) {
      return const _Check.fail(
        'SUPABASE_URL or SUPABASE_PUBLISHABLE_KEY is empty',
      );
    }
    final base = Uri.tryParse(url);
    if (base == null) {
      return const _Check.fail('SUPABASE_URL does not parse as a URL');
    }
    try {
      final response = await http
          .get(base.replace(path: '/auth/v1/health'), headers: {'apikey': key})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return const _Check.pass('reachable');
      return _Check.fail(
        'HTTP ${response.statusCode} — reachable, but check '
        'SUPABASE_PUBLISHABLE_KEY',
      );
    } catch (error, stack) {
      AppLogger.warn(_tag, 'Supabase reachability probe failed', error, stack);
      return _Check.fail('${error.runtimeType} — check SUPABASE_URL and your connection');
    }
  }

  /// The highest-value row: attempts the real native sign-in, in isolation,
  /// and reports exactly what comes back — then, only if it looks right,
  /// carries it all the way to a real Supabase exchange so the last
  /// ambiguity (Google vs. Supabase) is answered with evidence.
  ///
  /// Deliberately independent of `AuthRepository` — no shared helper, no
  /// import of it. This calls the same SDK the same way so the result means
  /// something, but it is diagnostic code, not the sign-in path, and it must
  /// stay free to prod at the SDK without anyone worrying it will change how
  /// a real sign-in behaves.
  Future<void> _probeGoogleToken() async {
    final signIn = GoogleSignIn.instance;

    try {
      await signIn.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId.isEmpty
            ? null
            : AppConfig.googleWebClientId,
      );
    } catch (error, stack) {
      AppLogger.error(_tag, 'probe initialize() failed', error, stack);
      _failProbe(
        code: 'initializeFailed',
        reason:
            'initialize() itself failed with ${error.runtimeType} — the '
            "client IDs aren't reaching the SDK at all.",
        raw: 'type=${error.runtimeType}\nerror=$error',
      );
      return;
    }

    if (!signIn.supportsAuthenticate()) {
      _failProbe(
        code: 'unsupportedPlatform',
        reason: "authenticate() isn't supported on this platform.",
        raw: 'supportsAuthenticate() returned false',
      );
      return;
    }

    final GoogleSignInAccount account;
    try {
      account = await signIn.authenticate();
    } on GoogleSignInException catch (error, stack) {
      final code = error.code.name;
      final raw = _formatGoogleException(error);
      AppLogger.error(
        _tag,
        'probe authenticate() failed code.name="$code"',
        error,
        stack,
      );
      if (code == 'canceled') {
        if (!mounted) return;
        setState(() {
          _probeOutcome = GoogleProbeOutcome.cancelled;
          _rawGoogleException = raw;
          _googleProbeCheck = const _Check.warn(
            'cancelled — the sheet was dismissed before it finished',
          );
          _audCheck = const _Check.unknown('not attempted — no token to read');
          _supabaseAcceptCheck = const _Check.unknown('not attempted');
        });
        return;
      }
      _failProbe(
        code: code,
        reason: AuthDiagnosticsVerdict.classifyRefusal(
          code: code,
          description: error.description,
        ),
        raw: raw,
      );
      return;
    } catch (error, stack) {
      AppLogger.error(
        _tag,
        'probe authenticate() failed non-Google ${error.runtimeType}',
        error,
        stack,
      );
      _failProbe(
        code: 'nonGoogleException',
        reason:
            '${error.runtimeType} — not a GoogleSignInException. See the '
            'raw exception below.',
        raw: 'type=${error.runtimeType}\nerror=$error',
      );
      return;
    }

    GoogleSignInClientAuthorization? authorization;
    try {
      authorization =
          await account.authorizationClient.authorizationForScopes(
            _googleProbeScopes,
          ) ??
          await account.authorizationClient.authorizeScopes(_googleProbeScopes);
    } catch (error, stack) {
      // Not fatal to the probe — the ID token is what the audience check
      // needs. Only the Supabase step below needs the access token, and it
      // already treats a missing authorization as "not attempted".
      AppLogger.warn(
        _tag,
        'probe authorizeScopes() failed — continuing without an access token',
        error,
        stack,
      );
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      _failProbe(
        code: 'missingIdToken',
        reason:
            'authenticate() succeeded but returned no ID token. On '
            "Android that points at serverClientId not reaching the "
            'native SDK.',
        raw: 'authenticate() returned an account with authentication.idToken == null',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _probeOutcome = GoogleProbeOutcome.issued;
      _googleProbeCheck = _Check.pass('issued an ID token (${idToken.length} chars)');
    });

    final aud = GoogleIdToken.decodeAudClaim(idToken);
    final expected = AppConfig.googleWebClientId;
    if (!mounted) return;
    setState(() {
      _observedAud = aud;
      if (aud == null) {
        _audMatches = null;
        _audCheck = const _Check.fail("couldn't decode the token's aud claim");
      } else {
        final matches = aud == expected;
        _audMatches = matches;
        _audCheck = matches
            ? _Check.pass('matches GOOGLE_WEB_CLIENT_ID')
            : _Check.fail('aud=$aud\ndoes not match GOOGLE_WEB_CLIENT_ID');
      }
    });

    if (aud == null || aud != expected) {
      setState(
        () => _supabaseAcceptCheck = const _Check.unknown(
          'not attempted — the audience check must pass first',
        ),
      );
      return;
    }
    if (authorization == null) {
      setState(
        () => _supabaseAcceptCheck = const _Check.unknown(
          "not attempted — authorizeScopes() didn't return an access token",
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _supabaseAcceptCheck = const _Check.checking());
    try {
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _supabaseOutcome = SupabaseAcceptOutcome.accepted;
        _supabaseAcceptCheck = _Check.pass(
          response.session == null
              ? 'accepted, but no session came back'
              : 'accepted — session established',
        );
      });
    } on AuthException catch (error, stack) {
      AppLogger.error(_tag, 'probe signInWithIdToken() failed', error, stack);
      if (!mounted) return;
      setState(() {
        _supabaseOutcome = SupabaseAcceptOutcome.rejected;
        _supabaseAcceptCheck = _Check.fail(
          'AuthException(${error.statusCode}): ${error.message}',
        );
      });
    }
  }

  void _failProbe({
    required String code,
    required String reason,
    required String raw,
  }) {
    if (!mounted) return;
    setState(() {
      _probeOutcome = GoogleProbeOutcome.refused;
      _refusalCode = code;
      _refusalReason = reason;
      _rawGoogleException = raw;
      _googleProbeCheck = _Check.fail(raw);
      _audCheck = const _Check.unknown('not attempted — no token to read');
      _supabaseAcceptCheck = const _Check.unknown('not attempted');
    });
  }

  String _formatGoogleException(GoogleSignInException error) =>
      'type=${error.runtimeType}\n'
      'code=${error.code.name}\n'
      'description=${error.description ?? '(none)'}\n'
      'details=${error.details ?? '(none)'}';

  /// The specific dashboard page a Google-side refusal points at — the row's
  /// [_ReportLine.note], distinct from the plain-language verdict headline.
  String? get _googleProbeDashboardHint {
    if (_probeOutcome != GoogleProbeOutcome.refused) return null;
    switch (_refusalCode) {
      case 'clientConfigurationError':
        return 'Fix in env.json → GOOGLE_WEB_CLIENT_ID, and Google Cloud '
            'Console → APIs & Services → Credentials.';
      case 'providerConfigurationError':
      case 'uiUnavailable':
        return 'Fix on the device: install or update Google Play services.';
      case 'userMismatch':
        return 'Fix on the device: sign out of the conflicting Google '
            'account first.';
      case 'unknownError':
        return 'Fix in Google Cloud Console → APIs & Services → OAuth '
            "consent screen → Test users, and → Credentials → the Android "
            "client's package name / SHA-1. Otherwise, fix on the device: "
            'Settings → Accounts → Add account → Google.';
      default:
        return null;
    }
  }

  // ------------------------------------------------------------- verdict ---

  String get _verdict => AuthDiagnosticsVerdict.headline(
    probe: _probeOutcome,
    refusalReason: _refusalReason,
    audMatches: _audMatches,
    supabaseOutcome: _supabaseOutcome,
  );

  _Status get _verdictStatus {
    switch (_probeOutcome) {
      case GoogleProbeOutcome.notRun:
        return _Status.unknown;
      case GoogleProbeOutcome.cancelled:
        return _Status.warn;
      case GoogleProbeOutcome.refused:
        return _Status.fail;
      case GoogleProbeOutcome.issued:
        final matches = _audMatches;
        if (matches == null) return _Status.warn;
        if (!matches) return _Status.fail;
        return switch (_supabaseOutcome) {
          SupabaseAcceptOutcome.notRun => _Status.warn,
          SupabaseAcceptOutcome.rejected => _Status.fail,
          SupabaseAcceptOutcome.accepted => _Status.pass,
        };
    }
  }

  // --------------------------------------------------------------- rows ---

  List<_ReportLine> _probeLines() => [
    _ReportLine(
      'Supabase reachable',
      _supabaseHealthCheck.detail,
      _supabaseHealthCheck.status,
      note: _supabaseHealthCheck.status == _Status.fail
          ? 'Fix in env.json (SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY), or '
                'Supabase Dashboard → Settings → API.'
          : null,
    ),
    _ReportLine(
      'Google token probe',
      _googleProbeCheck.detail,
      _googleProbeCheck.status,
      note: _googleProbeDashboardHint,
    ),
    _ReportLine(
      'Token audience (aud)',
      _audCheck.detail,
      _audCheck.status,
      note: _audCheck.status == _Status.fail
          ? 'Fix in env.json → GOOGLE_WEB_CLIENT_ID, diffed against Google '
                'Cloud Console → APIs & Services → Credentials.'
          : null,
    ),
    _ReportLine(
      'Supabase accepted the token',
      _supabaseAcceptCheck.detail,
      _supabaseAcceptCheck.status,
      note: _supabaseAcceptCheck.status == _Status.fail
          ? 'Fix in Supabase Dashboard → Authentication → Providers → '
                'Google → Client IDs.'
          : null,
    ),
  ];

  List<_ReportLine> _configLines() {
    final web = AppConfig.googleWebClientId;
    final ios = AppConfig.googleIosClientId;
    final webPrefix = GoogleConfigDiagnostics.projectNumberPrefix(web);
    final iosPrefix = GoogleConfigDiagnostics.projectNumberPrefix(ios);
    final bothPrefixed = webPrefix != null && iosPrefix != null;
    final samePrefix = bothPrefixed && webPrefix == iosPrefix;
    final packageInfo = _packageInfo;

    return [
      _ReportLine(
        'SUPABASE_URL',
        AppConfig.supabaseUrl.isEmpty ? 'MISSING' : AppConfig.supabaseUrl,
        AppConfig.supabaseUrl.isEmpty ? _Status.fail : _Status.pass,
        note: AppConfig.supabaseUrl.isEmpty
            ? 'Set in env.json. Copy from Supabase Dashboard → Settings → '
                  'API → Project URL.'
            : null,
      ),
      _ReportLine(
        'SUPABASE_PUBLISHABLE_KEY',
        AppConfig.supabasePublishableKey.isEmpty
            ? 'MISSING'
            : AppLogger.mask(AppConfig.supabasePublishableKey),
        AppConfig.supabasePublishableKey.isEmpty ? _Status.fail : _Status.pass,
        note: AppConfig.supabasePublishableKey.isEmpty
            ? 'Set in env.json. Copy from Supabase Dashboard → Settings → '
                  'API → Publishable (or anon) key.'
            : 'masked — this is the one value here that stays partial',
      ),
      _ReportLine(
        'GOOGLE_WEB_CLIENT_ID',
        web.isEmpty ? 'MISSING' : web,
        web.isEmpty
            ? _Status.fail
            : (GoogleConfigDiagnostics.hasPlausibleShape(web)
                  ? _Status.pass
                  : _Status.warn),
        note: web.isEmpty
            ? 'Set in env.json. Copy the Web client ID from Google Cloud '
                  'Console → APIs & Services → Credentials.'
            : 'shown in full — OAuth client IDs are public identifiers, not '
                  'secrets. Diff this character-by-character against Google '
                  'Cloud Console → Credentials.',
      ),
      _ReportLine(
        'GOOGLE_IOS_CLIENT_ID',
        ios.isEmpty ? 'MISSING' : ios,
        ios.isEmpty
            ? _Status.fail
            : (GoogleConfigDiagnostics.hasPlausibleShape(ios)
                  ? _Status.pass
                  : _Status.warn),
        note: ios.isEmpty
            ? 'Set in env.json. Copy the iOS client ID from Google Cloud '
                  'Console → APIs & Services → Credentials.'
            : null,
      ),
      _ReportLine(
        'Web project-number prefix',
        webPrefix ?? 'n/a',
        webPrefix == null ? _Status.warn : _Status.pass,
      ),
      _ReportLine(
        'iOS project-number prefix',
        iosPrefix ?? 'n/a',
        iosPrefix == null ? _Status.warn : _Status.pass,
      ),
      _ReportLine(
        'Web / iOS same Google Cloud project?',
        !bothPrefixed
            ? 'unknown — a prefix is missing above'
            : (samePrefix ? 'yes' : 'NO — different projects'),
        !bothPrefixed
            ? _Status.warn
            : (samePrefix ? _Status.pass : _Status.fail),
        note: bothPrefixed && !samePrefix
            ? 'The Web and iOS client IDs were issued under two different '
                  'Google Cloud projects. Fix in Google Cloud Console: '
                  'reissue both under the same project.'
            : null,
      ),
      _ReportLine(
        'Runtime package name',
        packageInfo == null ? 'loading…' : packageInfo.packageName,
        packageInfo == null
            ? _Status.checking
            : (packageInfo.packageName == _expectedApplicationId
                  ? _Status.pass
                  : _Status.fail),
        note:
            packageInfo != null &&
                packageInfo.packageName != _expectedApplicationId
            ? 'Expected $_expectedApplicationId (android/app/build.gradle.kts). '
                  'Fix in Google Cloud Console → Credentials → the Android '
                  "OAuth client's package name."
            : null,
      ),
    ];
  }

  // -------------------------------------------------------------- report ---

  String _buildReportText(List<_ReportLine> lines) {
    final buffer = StringBuffer()
      ..writeln('Prayer Walk — Google sign-in diagnostic report')
      ..writeln('Generated ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('VERDICT: $_verdict')
      ..writeln();
    for (final line in lines) {
      buffer.writeln('[${line.status.glyph}] ${line.label}: ${line.value}');
      if (line.note != null) buffer.writeln('    ${line.note}');
    }
    buffer
      ..writeln()
      ..writeln('Observed aud: ${_observedAud ?? 'n/a'}')
      ..writeln(
        'Runtime package name: ${_packageInfo?.packageName ?? 'not loaded'}',
      )
      ..writeln()
      ..writeln('Raw Google exception:')
      ..writeln(
        _rawGoogleException.isEmpty
            ? '(none captured this run — run all first)'
            : _rawGoogleException,
      )
      ..writeln()
      ..writeln('Native log capture (PowerShell):')
      ..writeln(_adbClearCommand)
      ..writeln(_adbFilterCommand);
    return buffer.toString();
  }

  Future<void> _copyReport(List<_ReportLine> lines) async {
    await Clipboard.setData(ClipboardData(text: _buildReportText(lines)));
    if (mounted) showAppSnackBar(context, 'Report copied.');
  }

  // ---------------------------------------------------------------- ui ---

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      // Unreachable through any of the normal entry points — the router only
      // registers this route in debug — but this screen must not do anything
      // useful if it is ever pushed some other way.
      return const Scaffold(
        body: Center(child: Text('Not available in this build.')),
      );
    }

    final theme = Theme.of(context);
    final configLines = _configLines();
    final probeLines = _probeLines();

    return Scaffold(
      appBar: AppBar(title: const Text('Google sign-in diagnostics')),
      body: ListView(
        padding: AppSpacing.listBody,
        children: [
          Text(
            'Reachable without signing in — this is the tool for when '
            "sign-in itself is what's broken. Configuration below is always "
            "current; the live probes need Run all. Its last two steps "
            'attempt a real Google sign-in and, if the token looks right, a '
            'real Supabase exchange — if everything passes, you end up '
            'signed in for real.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _VerdictCard(status: _verdictStatus, text: _verdict),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _runAll,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_running ? 'Running…' : 'Run all'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyReport([...configLines, ...probeLines]),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy report'),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Live probes',
            subtitle:
                'Run all to execute these. The Google and Supabase rows '
                'talk to the real services.',
          ),
          _CheckCard(lines: probeLines),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Configuration',
            subtitle: 'Read from this build directly — no probe needed.',
          ),
          _CheckCard(lines: configLines),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Native log capture',
            subtitle:
                'The Dart layer only ever sees a sanitised error. The real '
                'one — including which dashboard check failed — is in adb '
                'logcat. Run these in PowerShell while reproducing the '
                'failure:',
          ),
          _CommandBlock(command: _adbClearCommand),
          const SizedBox(height: AppSpacing.sm),
          _CommandBlock(command: _adbFilterCommand),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '"GetCredentialResponse error returned from framework" is the '
            'signature of a Credential Manager rejection — the line after it '
            'names the actual cause.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- checks ---

enum _Status {
  pass('✓'),
  warn('!'),
  fail('✗'),
  unknown('?'),
  checking('…');

  const _Status(this.glyph);
  final String glyph;

  Color color(ColorScheme scheme) => switch (this) {
    _Status.pass => Colors.green,
    _Status.warn => Colors.amber.shade800,
    _Status.fail => scheme.error,
    _Status.unknown => scheme.onSurfaceVariant,
    _Status.checking => scheme.onSurfaceVariant,
  };

  IconData get icon => switch (this) {
    _Status.pass => Icons.check_circle_outline,
    _Status.warn => Icons.warning_amber_rounded,
    _Status.fail => Icons.cancel_outlined,
    _Status.unknown => Icons.help_outline_rounded,
    _Status.checking => Icons.hourglass_empty_rounded,
  };
}

class _Check {
  const _Check.pass(this.detail) : status = _Status.pass;
  const _Check.warn(this.detail) : status = _Status.warn;
  const _Check.fail(this.detail) : status = _Status.fail;
  const _Check.unknown([this.detail = 'not run yet']) : status = _Status.unknown;
  const _Check.checking() : detail = 'checking…', status = _Status.checking;

  final String detail;
  final _Status status;
}

class _ReportLine {
  const _ReportLine(this.label, this.value, this.status, {this.note});

  final String label;
  final String value;
  final _Status status;
  final String? note;
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.status, required this.text});

  final _Status status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = status.color(theme.colorScheme);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.card,
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.lines});

  final List<_ReportLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [for (final line in lines) _CheckRow(line: line)],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.line});

  final _ReportLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = line.status.color(theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(line.status.icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SelectableText(
                  line.value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                if (line.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      line.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18),
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) showAppSnackBar(context, 'Copied.');
            },
          ),
        ],
      ),
    );
  }
}
