/// Every route in the app, named and deep-linkable.
///
/// Screens navigate with `context.goNamed(Routes.x)` / `pushNamed`, never with
/// literal paths — so a path can change here without a hunt through the tree.
abstract final class Routes {
  // ------------------------------------------------------------ auth flow ---
  static const splash = 'splash';
  static const splashPath = '/splash';

  static const onboarding = 'onboarding';
  static const onboardingPath = '/onboarding';

  static const signIn = 'signIn';
  static const signInPath = '/sign-in';

  // ---------------------------------------------------------- member shell ---
  static const feed = 'feed';
  static const feedPath = '/feed';

  static const devotionals = 'devotionals';
  static const devotionalsPath = '/devotionals';

  static const devotionalReader = 'devotionalReader';

  /// Relative to [devotionalsPath].
  static const devotionalReaderPath = ':devotionalId';

  static const record = 'record';
  static const recordPath = '/record';

  static const liveTracking = 'liveTracking';
  static const liveTrackingPath = 'live';

  static const activitySummary = 'activitySummary';
  static const activitySummaryPath = 'summary';

  static const history = 'history';
  static const historyPath = '/history';

  static const profile = 'profile';
  static const profilePath = '/profile';

  static const editProfile = 'editProfile';
  static const editProfilePath = 'edit';

  static const settings = 'settings';
  static const settingsPath = 'settings';

  // ------------------------------------------------- pushed, above the shell ---
  static const activityDetail = 'activityDetail';
  static const activityDetailPath = '/activity/:activityId';

  static const userProfile = 'userProfile';
  static const userProfilePath = '/people/:userId';

  static const followers = 'followers';
  static const followersPath = 'followers';

  static const following = 'following';
  static const followingPath = 'following';

  // ----------------------------------------------------------- admin shell ---
  static const adminDashboard = 'adminDashboard';
  static const adminDashboardPath = '/admin/dashboard';

  static const adminMembers = 'adminMembers';
  static const adminMembersPath = '/admin/members';

  static const adminMemberDetail = 'adminMemberDetail';
  static const adminMemberDetailPath = ':memberId';

  static const adminContent = 'adminContent';
  static const adminContentPath = '/admin/content';

  static const adminContentCreate = 'adminContentCreate';
  static const adminContentCreatePath = 'new';

  static const adminContentEdit = 'adminContentEdit';
  static const adminContentEditPath = ':devotionalId/edit';

  /// Scripture prompts live under Content: both are curated text, and the
  /// console has one place for that.
  static const adminScripture = 'adminScripture';
  static const adminScripturePath = 'scripture';

  static const adminScriptureCreate = 'adminScriptureCreate';
  static const adminScriptureCreatePath = 'new';

  static const adminScriptureEdit = 'adminScriptureEdit';
  static const adminScriptureEditPath = ':promptId/edit';

  static const adminModeration = 'adminModeration';
  static const adminModerationPath = '/admin/moderation';

  static const adminAnnouncements = 'adminAnnouncements';
  static const adminAnnouncementsPath = '/admin/announcements';

  static const adminAnnouncementCompose = 'adminAnnouncementCompose';
  static const adminAnnouncementComposePath = 'compose';

  static const adminSettings = 'adminSettings';
  static const adminSettingsPath = '/admin/settings';

  /// Everything under here belongs to the admin console.
  static const adminPrefix = '/admin';
}
