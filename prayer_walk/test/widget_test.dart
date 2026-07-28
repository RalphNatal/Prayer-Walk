import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/app.dart';
import 'support/mock_backend/seed_data.dart';
import 'package:prayer_walk/src/core/theme/app_typography.dart';
import 'package:prayer_walk/src/core/widgets/pilgrimage_card.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/auth/domain/profile.dart';
import 'package:prayer_walk/src/features/feed/data/feed_providers.dart';
import 'package:prayer_walk/src/features/feed/domain/feed_entry.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';

import 'support/stub_repositories.dart';

/// These exercise the *real* router redirect, but with the Supabase-backed auth
/// providers overridden — a widget test has no backend, and what's under test
/// here is the redirect's session/role gating, not the network.
ProviderScope _signedOutApp() => ProviderScope(
  overrides: [authPhaseProvider.overrideWith((ref) => AuthPhase.signedOut)],
  child: const PrayerWalkApp(),
);

/// One walk from someone you follow, so the feed the member lands on has
/// something on it. Built here rather than seeded: the feed is real now, and a
/// test that wants content has to say what the content is.
FeedEntry _entry() => FeedEntry(
  activity: Activity(
    id: 'b6f3e1a2-0000-4000-8000-000000000001',
    userId: 'b6f3e1a2-0000-4000-8000-0000000000aa',
    type: ActivityType.walk,
    title: 'Six laps before work',
    startedAt: DateTime.now().subtract(const Duration(hours: 2)),
    duration: const Duration(minutes: 42),
    distanceMeters: 4200,
    elevationGainMeters: 12,
    route: const [],
  ),
  author: UserProfile(
    id: 'b6f3e1a2-0000-4000-8000-0000000000aa',
    displayName: 'Ana Villanueva',
    handle: '@anav',
    role: UserRole.member,
    status: MemberStatus.active,
    joinedAt: DateTime.now().subtract(const Duration(days: 30)),
    accentIndex: 2,
  ),
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
    // Reading the real one would touch `Supabase.instance`, which is not
    // initialized in a test.
    currentAuthUserIdProvider.overrideWith((ref) => MockSeed.currentUserId),
    feedRepositoryProvider.overrideWith(
      (ref) => StubFeedRepository([_entry()]),
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
