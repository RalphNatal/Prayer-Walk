import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/activity_detail_screen.dart';
import '../../features/activity/presentation/activity_summary_screen.dart';
import '../../features/activity/presentation/history_screen.dart';
import '../../features/activity/presentation/live_tracking_screen.dart';
import '../../features/activity/presentation/record_screen.dart';
import '../../features/admin/presentation/admin_announcement_compose_screen.dart';
import '../../features/admin/presentation/admin_announcements_screen.dart';
import '../../features/admin/presentation/admin_content_form_screen.dart';
import '../../features/admin/presentation/admin_content_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_member_detail_screen.dart';
import '../../features/admin/presentation/admin_members_screen.dart';
import '../../features/admin/presentation/admin_moderation_screen.dart';
import '../../features/admin/presentation/admin_settings_screen.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/devotionals/presentation/devotional_reader_screen.dart';
import '../../features/devotionals/presentation/devotionals_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/follow_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/profile/presentation/user_profile_screen.dart';
import 'admin_shell.dart';
import 'member_shell.dart';
import 'not_found_screen.dart';
import 'routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// One router for both experiences. Which shell you land in is decided by
/// [redirect] reading the role provider — in this phase, the dev role switcher.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splashPath,
    refreshListenable: refresh,
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: Routes.splashPath,
        name: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboardingPath,
        name: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.signInPath,
        name: Routes.signIn,
        builder: (context, state) => const AuthScreen(),
      ),

      // Pushed above whichever shell is showing.
      GoRoute(
        path: Routes.activityDetailPath,
        name: Routes.activityDetail,
        builder: (context, state) => ActivityDetailScreen(
          activityId: state.pathParameters['activityId']!,
        ),
      ),
      GoRoute(
        path: Routes.userProfilePath,
        name: Routes.userProfile,
        builder: (context, state) =>
            UserProfileScreen(userId: state.pathParameters['userId']!),
        routes: [
          GoRoute(
            path: Routes.followersPath,
            name: Routes.followers,
            builder: (context, state) => FollowListScreen(
              userId: state.pathParameters['userId']!,
              mode: FollowListMode.followers,
            ),
          ),
          GoRoute(
            path: Routes.followingPath,
            name: Routes.following,
            builder: (context, state) => FollowListScreen(
              userId: state.pathParameters['userId']!,
              mode: FollowListMode.following,
            ),
          ),
        ],
      ),

      _memberShell,
      _adminShell,
    ],
  );
});

// ---------------------------------------------------------------- member ---

final _memberShell = StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      MemberShell(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.feedPath,
          name: Routes.feed,
          builder: (context, state) => const FeedScreen(),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.devotionalsPath,
          name: Routes.devotionals,
          builder: (context, state) => const DevotionalsScreen(),
          routes: [
            GoRoute(
              path: Routes.devotionalReaderPath,
              name: Routes.devotionalReader,
              // Full screen: reading is not a tabbed activity.
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => DevotionalReaderScreen(
                devotionalId: state.pathParameters['devotionalId']!,
              ),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.recordPath,
          name: Routes.record,
          builder: (context, state) => const RecordScreen(),
          routes: [
            GoRoute(
              path: Routes.liveTrackingPath,
              name: Routes.liveTracking,
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const LiveTrackingScreen(),
            ),
            GoRoute(
              path: Routes.activitySummaryPath,
              name: Routes.activitySummary,
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const ActivitySummaryScreen(),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.historyPath,
          name: Routes.history,
          builder: (context, state) => const HistoryScreen(),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.profilePath,
          name: Routes.profile,
          builder: (context, state) => const ProfileScreen(),
          routes: [
            GoRoute(
              path: Routes.editProfilePath,
              name: Routes.editProfile,
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const EditProfileScreen(),
            ),
            GoRoute(
              path: Routes.settingsPath,
              name: Routes.settings,
              parentNavigatorKey: _rootNavigatorKey,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

// ----------------------------------------------------------------- admin ---

final _adminShell = StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      AdminShell(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminDashboardPath,
          name: Routes.adminDashboard,
          builder: (context, state) => const AdminDashboardScreen(),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminMembersPath,
          name: Routes.adminMembers,
          builder: (context, state) => const AdminMembersScreen(),
          routes: [
            GoRoute(
              path: Routes.adminMemberDetailPath,
              name: Routes.adminMemberDetail,
              builder: (context, state) => AdminMemberDetailScreen(
                memberId: state.pathParameters['memberId']!,
              ),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminContentPath,
          name: Routes.adminContent,
          builder: (context, state) => const AdminContentScreen(),
          routes: [
            GoRoute(
              path: Routes.adminContentCreatePath,
              name: Routes.adminContentCreate,
              builder: (context, state) => const AdminContentFormScreen(),
            ),
            GoRoute(
              path: Routes.adminContentEditPath,
              name: Routes.adminContentEdit,
              builder: (context, state) => AdminContentFormScreen(
                devotionalId: state.pathParameters['devotionalId'],
              ),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminModerationPath,
          name: Routes.adminModeration,
          builder: (context, state) => const AdminModerationScreen(),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminAnnouncementsPath,
          name: Routes.adminAnnouncements,
          builder: (context, state) => const AdminAnnouncementsScreen(),
          routes: [
            GoRoute(
              path: Routes.adminAnnouncementComposePath,
              name: Routes.adminAnnouncementCompose,
              builder: (context, state) =>
                  const AdminAnnouncementComposeScreen(),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: Routes.adminSettingsPath,
          name: Routes.adminSettings,
          builder: (context, state) => const AdminSettingsScreen(),
        ),
      ],
    ),
  ],
);

// -------------------------------------------------------------- redirect ---

const _authLocations = {
  Routes.splashPath,
  Routes.onboardingPath,
  Routes.signInPath,
};

/// Decides, on every navigation, whether you may be where you are going.
///
/// This is a convenience gate, not the security boundary — RLS and the profiles
/// trigger are server-authoritative. It only chooses *which shell to show*:
/// holds on the splash until the session and then the role resolve; sends a
/// signed-out person through onboarding (once per run) into sign-in; and pins a
/// signed-in person to the shell their real `profiles.role` belongs to.
String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  final phase = ref.read(authPhaseProvider);

  // Session itself not resolved yet (defensive — normally resolves synchronously
  // from the restored session).
  if (phase == AuthPhase.loading) {
    return location == Routes.splashPath ? null : Routes.splashPath;
  }

  // Signed out: onboarding first (once), then the sign-in screen. Never a shell.
  if (phase == AuthPhase.signedOut) {
    if (!ref.read(onboardingSeenProvider)) {
      return location == Routes.onboardingPath ? null : Routes.onboardingPath;
    }
    return location == Routes.signInPath ? null : Routes.signInPath;
  }

  // Signed in: wait for the profile row (role) before choosing a shell, holding
  // on the splash so the member shell never flashes ahead of an admin redirect.
  final profile = ref.read(authProfileProvider);
  if (profile.isLoading) {
    return location == Routes.splashPath ? null : Routes.splashPath;
  }

  // Resolved. Default to the member experience unless the row positively says
  // admin — a transient profile-read error degrades to member rather than a
  // stuck splash, and the server still enforces the real gate.
  final isAdmin = profile.value?.role == UserRole.admin;
  final home = isAdmin ? Routes.adminDashboardPath : Routes.feedPath;

  if (_authLocations.contains(location)) return home;

  final inAdminArea = location.startsWith(Routes.adminPrefix);
  if (inAdminArea != isAdmin) return home;

  return null;
}

/// Bridges Riverpod changes to `GoRouter`'s refresh mechanism.
///
/// Only the three things the redirect reads are listened to, so navigating does
/// not rebuild the router.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authPhaseProvider, (_, _) => notifyListeners());
    ref.listen(authProfileProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
  }
}
