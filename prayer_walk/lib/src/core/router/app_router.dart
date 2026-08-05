import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../../features/admin/presentation/admin_scripture_form_screen.dart';
import '../../features/admin/presentation/admin_scripture_screen.dart';
import '../../features/admin/presentation/admin_scripture_submissions_screen.dart';
import '../../features/admin/presentation/admin_settings_screen.dart';
import '../../features/auth/data/auth_providers.dart';
import '../../features/auth/presentation/auth_diagnostics_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/devotionals/presentation/devotional_reader_screen.dart';
import '../../features/devotionals/presentation/devotionals_screen.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/privacy/presentation/blocked_members_screen.dart';
import '../../features/privacy/presentation/privacy_zones_screen.dart';
import '../../features/privacy/presentation/safety_screen.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/profile/presentation/delete_account_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/follow_list_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/profile/presentation/user_profile_screen.dart';
import '../../features/scripture/presentation/my_submissions_screen.dart';
import '../../features/scripture/presentation/submit_scripture_screen.dart';
import 'admin_shell.dart';
import 'member_shell.dart';
import 'not_found_screen.dart';
import 'page_transitions.dart';
import 'routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// One router for both experiences. Which shell you land in is decided by
/// [redirect] reading the role provider — in this phase, the dev role switcher.
///
/// Routes that use `pageBuilder` rather than `builder` are opting into the
/// app's transition vocabulary (see `page_transitions.dart`): a fade-through
/// for anything pushed on top of what you were reading, and the one directional
/// move for record → live → summary. The rest keep `builder`, which is correct
/// for them — a shell branch's root has no transition of its own.
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

      // Debug-only, and deliberately top-level rather than nested under
      // sign-in: a route nested anywhere inside the authenticated shells
      // would be exactly what [_redirect] bounces a signed-out visitor away
      // from, which is the one thing a tool for diagnosing broken sign-in
      // cannot tolerate. `AuthDiagnosticsScreen` gates its own body on
      // kDebugMode too, as a second line of defence if this route is ever
      // reached some other way.
      if (kDebugMode)
        GoRoute(
          path: Routes.authDiagnosticsPath,
          name: Routes.authDiagnostics,
          builder: (context, state) => const AuthDiagnosticsScreen(),
        ),

      // Pushed above whichever shell is showing.
      GoRoute(
        path: Routes.activityDetailPath,
        name: Routes.activityDetail,
        pageBuilder: (context, state) => fadeThroughPage(
          context,
          state,
          ActivityDetailScreen(activityId: state.pathParameters['activityId']!),
        ),
      ),
      GoRoute(
        path: Routes.userProfilePath,
        name: Routes.userProfile,
        pageBuilder: (context, state) => fadeThroughPage(
          context,
          state,
          UserProfileScreen(userId: state.pathParameters['userId']!),
        ),
        routes: [
          GoRoute(
            path: Routes.followersPath,
            name: Routes.followers,
            pageBuilder: (context, state) => fadeThroughPage(
              context,
              state,
              FollowListScreen(
                userId: state.pathParameters['userId']!,
                mode: FollowListMode.followers,
              ),
            ),
          ),
          GoRoute(
            path: Routes.followingPath,
            name: Routes.following,
            pageBuilder: (context, state) => fadeThroughPage(
              context,
              state,
              FollowListScreen(
                userId: state.pathParameters['userId']!,
                mode: FollowListMode.following,
              ),
            ),
          ),
        ],
      ),

      // Discovery and the safety screens are pushed above the shell rather
      // than given tabs. Finding people is a door out of an empty feed, not a
      // fifth place to live; the zone and block screens are settings that
      // happen to need a whole screen.
      GoRoute(
        path: Routes.discoverPath,
        name: Routes.discover,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const DiscoverScreen()),
      ),
      GoRoute(
        path: Routes.privacyZonesPath,
        name: Routes.privacyZones,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const PrivacyZonesScreen()),
      ),
      GoRoute(
        path: Routes.blockedMembersPath,
        name: Routes.blockedMembers,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const BlockedMembersScreen()),
      ),
      GoRoute(
        path: Routes.deleteAccountPath,
        name: Routes.deleteAccount,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const DeleteAccountScreen()),
      ),
      GoRoute(
        path: Routes.submitScripturePath,
        name: Routes.submitScripture,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const SubmitScriptureScreen()),
      ),
      GoRoute(
        path: Routes.myScriptureSubmissionsPath,
        name: Routes.myScriptureSubmissions,
        pageBuilder: (context, state) =>
            fadeThroughPage(context, state, const MySubmissionsScreen()),
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
              pageBuilder: (context, state) => fadeThroughPage(
                context,
                state,
                DevotionalReaderScreen(
                  devotionalId: state.pathParameters['devotionalId']!,
                ),
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
            // The one forward-moving sequence in the app: choose what you
            // carry, walk it, read it back. These two get the directional
            // transition, and nothing else in the app does — which is what
            // keeps the direction meaningful.
            GoRoute(
              path: Routes.liveTrackingPath,
              name: Routes.liveTracking,
              parentNavigatorKey: _rootNavigatorKey,
              pageBuilder: (context, state) =>
                  forwardPage(context, state, const LiveTrackingScreen()),
            ),
            GoRoute(
              path: Routes.activitySummaryPath,
              name: Routes.activitySummary,
              parentNavigatorKey: _rootNavigatorKey,
              pageBuilder: (context, state) =>
                  forwardPage(context, state, const ActivitySummaryScreen()),
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
              pageBuilder: (context, state) =>
                  fadeThroughPage(context, state, const EditProfileScreen()),
            ),
            GoRoute(
              path: Routes.settingsPath,
              name: Routes.settings,
              parentNavigatorKey: _rootNavigatorKey,
              pageBuilder: (context, state) =>
                  fadeThroughPage(context, state, const SettingsScreen()),
              routes: [
                GoRoute(
                  path: Routes.safetyPath,
                  name: Routes.safety,
                  parentNavigatorKey: _rootNavigatorKey,
                  pageBuilder: (context, state) =>
                      fadeThroughPage(context, state, const SafetyScreen()),
                ),
              ],
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
              pageBuilder: (context, state) => fadeThroughPage(
                context,
                state,
                AdminMemberDetailScreen(
                  memberId: state.pathParameters['memberId']!,
                ),
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
              pageBuilder: (context, state) => fadeThroughPage(
                context,
                state,
                const AdminContentFormScreen(),
              ),
            ),
            GoRoute(
              path: Routes.adminContentEditPath,
              name: Routes.adminContentEdit,
              pageBuilder: (context, state) => fadeThroughPage(
                context,
                state,
                AdminContentFormScreen(
                  devotionalId: state.pathParameters['devotionalId'],
                ),
              ),
            ),
            GoRoute(
              path: Routes.adminScripturePath,
              name: Routes.adminScripture,
              pageBuilder: (context, state) =>
                  fadeThroughPage(context, state, const AdminScriptureScreen()),
              routes: [
                GoRoute(
                  path: Routes.adminScriptureCreatePath,
                  name: Routes.adminScriptureCreate,
                  pageBuilder: (context, state) => fadeThroughPage(
                    context,
                    state,
                    const AdminScriptureFormScreen(),
                  ),
                ),
                // Before the `:promptId/edit` route, so the literal segment
                // wins: `/admin/content/scripture/submissions` must not be
                // matched as a prompt id.
                GoRoute(
                  path: Routes.adminScriptureSubmissionsPath,
                  name: Routes.adminScriptureSubmissions,
                  pageBuilder: (context, state) => fadeThroughPage(
                    context,
                    state,
                    const AdminScriptureSubmissionsScreen(),
                  ),
                ),
                GoRoute(
                  path: Routes.adminScriptureEditPath,
                  name: Routes.adminScriptureEdit,
                  pageBuilder: (context, state) => fadeThroughPage(
                    context,
                    state,
                    AdminScriptureFormScreen(
                      promptId: state.pathParameters['promptId'],
                    ),
                  ),
                ),
              ],
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
              pageBuilder: (context, state) => fadeThroughPage(
                context,
                state,
                const AdminAnnouncementComposeScreen(),
              ),
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

  // Reachable regardless of session state, loading or otherwise — the entire
  // point of this screen is to be usable when sign-in itself is broken, so it
  // cannot be gated behind the sign-in it exists to diagnose. The route is
  // only ever registered in debug builds (see the router's route list), so
  // this branch is dead code in release regardless.
  if (location == Routes.authDiagnosticsPath) return null;

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
