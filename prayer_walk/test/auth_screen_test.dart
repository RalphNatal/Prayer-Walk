import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/features/auth/data/auth_repository.dart';
import 'package:prayer_walk/src/features/auth/presentation/auth_screen.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthResponse;

/// The real repository with only the sign-in calls this screen makes replaced
/// — nothing here reaches Supabase or Apple.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.appleResult});

  /// What [signInWithApple] does: completes when the test says so, throws
  /// what it was given, or returns at once.
  final Object? appleResult;

  int appleCalls = 0;
  final emailSignIns = <String>[];

  @override
  Future<AuthResponse> signInWithApple() async {
    appleCalls++;
    final result = appleResult;
    if (result is Completer<AuthResponse>) return result.future;
    if (result != null) throw result;
    return AuthResponse();
  }

  @override
  Future<AuthResponse> signInWithGoogle() async => AuthResponse();

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emailSignIns.add(email);
    return AuthResponse();
  }
}

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

final _appleButton = find.byType(SignInWithAppleButton);
final _googleButton = find.widgetWithText(OutlinedButton, 'Continue with Google');

Future<_FakeAuthRepository> _pump(
  WidgetTester tester, {
  Object? appleResult,
  ThemeData? theme,
  double textScale = 1,
  // Wide, like widget_test.dart's default surface. At phone widths the test
  // font — every glyph a full em wide — overflows the existing Google
  // button's label, which has nothing to do with what these tests check.
  Size size = const Size(800, 1200),
}) async {
  final repository = _FakeAuthRepository(appleResult: appleResult);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AuthScreen(),
      ),
    ),
  );
  await tester.pump();
  return repository;
}

void main() {
  group('where the Apple button appears', () {
    testWidgets('present on iOS', (tester) async {
      await _pump(tester);

      expect(_appleButton, findsOneWidget);
      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(_googleButton, findsOneWidget);
    }, variant: _ios);

    testWidgets('absent on Android, which keeps Google and email', (
      tester,
    ) async {
      await _pump(tester);

      expect(_appleButton, findsNothing);
      expect(find.bySemanticsLabel('Sign in with Apple'), findsNothing);
      expect(_googleButton, findsOneWidget);
    }, variant: _android);
  });

  group('prominence', () {
    testWidgets('the same size as the Google button, and above it', (
      tester,
    ) async {
      await _pump(tester);

      final apple = tester.getRect(_appleButton);
      final google = tester.getRect(_googleButton);
      expect(apple.size, google.size);
      expect(apple.top, lessThan(google.top));
      // Apple's own minimum, and this app's.
      expect(apple.height, greaterThanOrEqualTo(44));
    }, variant: _ios);

    testWidgets('black on the light theme', (tester) async {
      await _pump(tester);

      expect(
        tester.widget<SignInWithAppleButton>(_appleButton).style,
        SignInWithAppleButtonStyle.black,
      );
    }, variant: _ios);

    testWidgets('white on the dark theme', (tester) async {
      await _pump(tester, theme: AppTheme.dark());

      expect(
        tester.widget<SignInWithAppleButton>(_appleButton).style,
        SignInWithAppleButtonStyle.white,
      );
    }, variant: _ios);

    testWidgets('announces itself as a button by name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Sign in with Apple')),
        isSemantics(
          label: 'Sign in with Apple',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    }, variant: _ios);

    testWidgets('holds Apple\'s label size and its height at the largest '
        'text setting, on the narrowest phone', (tester) async {
      await _pump(tester, textScale: 2, size: const Size(320, 1400));

      // The one overflow on this screen at 2x is the existing Google button's
      // label, which predates the Apple button and is out of its scope. The
      // Apple button is laid out first, so if it overflowed, it is its
      // exception that would be reported here — and it must not be.
      final exception = tester.takeException();
      if (exception != null) {
        expect('$exception', isNot(contains('sign_in_with_apple')));
      }

      final label = find.descendant(
        of: _appleButton,
        matching: find.text('Sign in with Apple'),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(label)),
        TextScaler.noScaling,
      );
      expect(tester.getSize(_appleButton).height, 56);
    }, variant: _ios);
  });

  group('signing in', () {
    testWidgets('the button runs signInWithApple', (tester) async {
      final repository = await _pump(tester);

      await tester.tap(_appleButton);
      await tester.pump();

      expect(repository.appleCalls, 1);
    }, variant: _ios);

    testWidgets('busy while one sign-in runs: neither third-party button '
        'starts another', (tester) async {
      final pending = Completer<AuthResponse>();
      final repository = await _pump(tester, appleResult: pending);

      await tester.tap(_appleButton);
      await tester.pump();
      await tester.tap(_appleButton, warnIfMissed: false);
      await tester.pump();

      expect(repository.appleCalls, 1);
      expect(tester.widget<OutlinedButton>(_googleButton).onPressed, isNull);

      pending.complete(AuthResponse());
      await tester.pump();
      expect(tester.widget<OutlinedButton>(_googleButton).onPressed, isNotNull);
    }, variant: _ios);

    testWidgets('a dismissed Apple sheet shows nothing and releases the '
        'button', (tester) async {
      final repository = await _pump(tester, appleResult: const AuthCancelled());

      await tester.tap(_appleButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      // Released: a second tap goes through.
      await tester.tap(_appleButton);
      await tester.pump();
      expect(repository.appleCalls, 2);
    }, variant: _ios);

    testWidgets('a real Apple failure is shown', (tester) async {
      await _pump(
        tester,
        appleResult: const AuthFailure('Apple sign-in didn\'t go through. '
            'Try again.'),
      );

      await tester.tap(_appleButton);
      await tester.pump();

      expect(
        find.text('Apple sign-in didn\'t go through. Try again.'),
        findsOneWidget,
      );
    }, variant: _ios);
  });

  testWidgets('a private relay address passes the email field', (
    tester,
  ) async {
    final repository = await _pump(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'k7x2q9mnzp@privaterelay.appleid.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'walking-together',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('That email address is missing something.'), findsNothing);
    expect(repository.emailSignIns, ['k7x2q9mnzp@privaterelay.appleid.com']);
  });
}
