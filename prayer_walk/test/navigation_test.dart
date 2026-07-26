import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/app.dart';
import 'package:prayer_walk/src/core/mock_backend/mock_backend.dart';
import 'package:prayer_walk/src/core/mock_backend/seed_data.dart';
import 'package:prayer_walk/src/core/theme/app_typography.dart';
import 'package:prayer_walk/src/core/widgets/pilgrimage_card.dart';
import 'package:prayer_walk/src/features/activity/data/mock_activity_repository.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/auth/domain/profile.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';

/// Reachability tests for both shells.
///
/// Auth is faked with provider overrides (a widget test has no Supabase), so
/// each test boots straight into the shell its role belongs to — which is also
/// a live check that the role-driven redirect sends each role to the right
/// place. These deliberately stay off the map-backed screens (record, live,
/// summary, activity detail): mounting `flutter_map` fires tile requests that
/// cannot succeed offline. Those screens are covered by walking the app.
///
/// Activities now come from Supabase, which a widget test also has no access
/// to, so the repository is swapped for the seeded one at the interface — the
/// point of the seam. History is therefore still asserted against seed data;
/// what changed is that it arrives through an override rather than by default.
ProviderScope _appAs(UserRole role) => ProviderScope(
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
    activityRepositoryProvider.overrideWith(
      (ref) => MockActivityRepository(
        ref.watch(mockBackendProvider),
        MockSeed.currentUserId,
      ),
    ),
  ],
  child: const PrayerWalkApp(),
);

void main() {
  setUpAll(AppTypography.useBundledFonts);
  tearDownAll(AppTypography.useNetworkFonts);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> boot(WidgetTester tester, UserRole role) async {
    await tester.pumpWidget(_appAs(role));
    await settle(tester);
    await settle(tester);
  }

  testWidgets('the member shell reaches devotionals and opens a reader', (
    tester,
  ) async {
    await boot(tester, UserRole.member);

    await tester.tap(
      find.widgetWithIcon(NavigationDestination, Icons.auto_stories_outlined),
    );
    await settle(tester);
    expect(find.text('Devotionals'), findsWidgets);

    await tester.tap(find.text('Before the street wakes'));
    await settle(tester);
    expect(find.text('Start a walk with this'), findsOneWidget);
    expect(find.text('Lamentations 3:22-23'), findsOneWidget);
  });

  testWidgets('history filters by activity type', (tester) async {
    await boot(tester, UserRole.member);

    await tester.tap(
      find.widgetWithIcon(NavigationDestination, Icons.route_outlined),
    );
    await settle(tester);
    expect(find.byType(PilgrimageCard), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Hike'));
    await settle(tester);
    expect(find.text('Antipolo climb with Tita'), findsOneWidget);
    expect(find.text('Six laps before work'), findsNothing);
  });

  testWidgets('an admin is routed to the console, not the member shell', (
    tester,
  ) async {
    await boot(tester, UserRole.admin);

    // Member bottom nav is gone; the admin console is showing.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Total members'), findsOneWidget);
  });

  testWidgets('the admin shell shows a rail at tablet width', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await boot(tester, UserRole.admin);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);

    // The rail navigates branches. Tap the destination's label directly — on
    // the dashboard 'Content' only appears in the rail, so this is unambiguous
    // (tapping the NavigationRail widget itself would hit its centre, a
    // different destination).
    await tester.tap(find.text('Content'));
    await settle(tester);
    expect(find.text('Published'), findsWidgets);
    expect(find.text('Draft'), findsWidgets);
  });
}
