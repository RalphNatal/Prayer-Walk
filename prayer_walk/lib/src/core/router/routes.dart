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

  /// Debug-only. Registered as a top-level route (not inside a shell) and
  /// explicitly exempted in the router's redirect, so it stays reachable
  /// with no session — see `AuthDiagnosticsScreen`'s doc comment for why
  /// that's the point of it.
  static const authDiagnostics = 'authDiagnostics';
  static const authDiagnosticsPath = '/auth-diagnostics';

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

  /// Who sees your walks, where they are trimmed, and who is shut out.
  /// Reachable from Settings and from the first-public-walk explanation.
  static const safety = 'safety';
  static const safetyPath = 'safety';

  static const privacyZones = 'privacyZones';
  static const privacyZonesPath = '/privacy-zones';

  static const blockedMembers = 'blockedMembers';
  static const blockedMembersPath = '/blocked';

  static const deleteAccount = 'deleteAccount';
  static const deleteAccountPath = '/delete-account';

  /// Finding people and churches. Pushed above the shell rather than given a
  /// tab: it is a door out of an empty feed, not a sixth place to live.
  static const discover = 'discover';
  static const discoverPath = '/discover';

  /// `?tab=churches` opens Discover on its Churches tab — the door the profile
  /// and the empty states use when what somebody wants is their church.
  static const discoverTabParam = 'tab';
  static const discoverChurchesTab = 'churches';

  // ------------------------------------------------------------ churches ---
  //
  // Church groups live inside Discover rather than in a tab of their own: the
  // bottom bar already has five destinations, and a church is somewhere you
  // join once and then mostly meet through its scripture on your walks — it is
  // a door, like Discover, not a place you go back to every day.

  /// Starting a group. Registered before [churchGroupPath] so the literal
  /// segment wins: `/churches/new` must not be read as a group id.
  static const createChurchGroup = 'createChurchGroup';
  static const createChurchGroupPath = '/churches/new';

  /// One church's group. Pushed above whichever shell is showing, like a
  /// member's profile.
  static const churchGroup = 'churchGroup';
  static const churchGroupPath = '/churches/:groupId';

  static const editChurchGroup = 'editChurchGroup';
  static const editChurchGroupPath = 'edit';

  static const churchGroupMembers = 'churchGroupMembers';
  static const churchGroupMembersPath = 'members';

  /// A group admin's own scripture for their group. Nothing under here reaches
  /// the global library or the console — see the header of
  /// `20261016010000_church_groups.sql`.
  static const churchGroupScripture = 'churchGroupScripture';
  static const churchGroupScripturePath = 'scripture';

  static const churchGroupScriptureCompose = 'churchGroupScriptureCompose';
  static const churchGroupScriptureComposePath = 'new';

  static const churchGroupScriptureEdit = 'churchGroupScriptureEdit';
  static const churchGroupScriptureEditPath = ':promptId/edit';

  /// A member proposing a scripture prompt for review.
  static const submitScripture = 'submitScripture';
  static const submitScripturePath = '/submit-scripture';

  static const myScriptureSubmissions = 'myScriptureSubmissions';
  static const myScriptureSubmissionsPath = '/my-submissions';

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

  /// The member submissions queue. Under Scripture, because approving one is
  /// the same act as writing one — it puts text into other people's walks.
  static const adminScriptureSubmissions = 'adminScriptureSubmissions';
  static const adminScriptureSubmissionsPath = 'submissions';

  static const adminModeration = 'adminModeration';
  static const adminModerationPath = '/admin/moderation';

  /// A reported church group, opened from the queue: what it is, what it has
  /// published, and the controls to unpublish or remove it. Under Moderation
  /// because the only reason the console looks inside a group is a report.
  static const adminGroupReview = 'adminGroupReview';
  static const adminGroupReviewPath = 'group/:groupId';

  static const adminAnnouncements = 'adminAnnouncements';
  static const adminAnnouncementsPath = '/admin/announcements';

  static const adminAnnouncementCompose = 'adminAnnouncementCompose';
  static const adminAnnouncementComposePath = 'compose';

  static const adminSettings = 'adminSettings';
  static const adminSettingsPath = '/admin/settings';

  /// Everything under here belongs to the admin console.
  static const adminPrefix = '/admin';
}
