import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/app.dart';
import 'package:prayer_walk/src/core/mock_backend/seed_data.dart';
import 'package:prayer_walk/src/core/theme/app_typography.dart';
import 'package:prayer_walk/src/core/widgets/pilgrimage_card.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/auth/domain/profile.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';

/// These exercise the *real* router redirect, but with the Supabase-backed auth
/// providers overridden — a widget test has no backend, and what's under test
/// here is the redirect's session/role gating, not the network.
ProviderScope _signedOutApp() => ProviderScope(
  overrides: [authPhaseProvider.overrideWith((ref) => AuthPhase.signedOut)],
  child: const PrayerWalkApp(),
);

ProviderScope _signedInApp(UserRole role) => ProviderScope(
  overrides: [
    authPhaseProvider.overrideWith((ref) => AuthPhase.signedIn),
    authProfileProvider.overrideWith(
      (ref) async => Profile(
        id: MockSeed.currentUserId,
        fullName: 'Maria Reyes',
        role: role,
      ),
    ),
  ],
  child: const PrayerWalkApp(),
);

void main() {
  // Resolve fonts by name rather than fetching them — no test touches the
  // network, and the map layer is never mounted by these flows.
  setUpAll(AppTypography.useBundledFonts);
  tearDownAll(AppTypography.useNetworkFonts);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> boot(WidgetTester tester, ProviderScope app) async {
    await tester.pumpWidget(app);
    await settle(tester);
  }

  testWidgets('a signed-out first run lands on onboarding', (tester) async {
    await boot(tester, _signedOutApp());

    expect(find.text('Walk it, and mean it'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('skipping onboarding reaches the sign-in form', (tester) async {
    await boot(tester, _signedOutApp());

    await tester.tap(find.text('Skip'));
    await settle(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('a signed-in member is routed to the feed', (tester) async {
    await boot(tester, _signedInApp(UserRole.member));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(PilgrimageCard), findsWidgets);
  });
}
