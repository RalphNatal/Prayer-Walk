import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/core/widgets/stat_tile.dart';
import 'package:prayer_walk/src/features/activity/data/activity_providers.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/data/recording_controller.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/activity/domain/activity_repository.dart';
import 'package:prayer_walk/src/features/activity/presentation/activity_detail_screen.dart';
import 'package:prayer_walk/src/features/activity/presentation/activity_summary_screen.dart';
import 'package:prayer_walk/src/features/activity/presentation/live_tracking_screen.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_settings.dart';
import 'package:prayer_walk/src/features/profile/data/profile_providers.dart';
import 'package:prayer_walk/src/features/profile/domain/profile_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:prayer_walk/src/features/profile/presentation/widgets/profile_pieces.dart';
import 'package:prayer_walk/src/features/social/data/social_providers.dart';

import 'support/stub_repositories.dart';

/// Nothing on a screen may run off the side of it.
///
/// Flutter reports a `RenderFlex` overflow as a thrown exception in tests, so
/// `takeException()` returning null is the assertion — the yellow-and-black
/// stripe on the device and a failure here are the same event.
///
/// The widths are the real ones: 320dp is the narrowest phone still in the
/// wild, 384dp is the device the summary screen's stat strip overflowed on
/// (720px at 1.875), 412dp a current Pixel, and 800dp a tablet. The scales are
/// the default, one notch of "larger text", and the accessibility maximum.
const _widths = <double>[320, 360, 384, 412, 800];
const _scales = <double>[1.0, 1.3, 2.0];

const _viewerId = 'b6f3e1a2-0000-4000-8000-00000000000a';
const _activityId = 'b6f3e1a2-0000-4000-8000-000000000001';

/// The walk from the bug report: 1.21 km in 20:13, 108 m of climb — which is a
/// pace of 16:40 /km, the widest readout a stat tile carries.
ActivityDraft _reportedDraft() => ActivityDraft(
  type: ActivityType.walk,
  title: 'Morning walk in Antipolo',
  startedAt: DateTime(2026, 7, 27, 6, 4),
  duration: const Duration(minutes: 20, seconds: 13),
  // 1213 m in 1213 s reads as 1.21 km at a pace of exactly 16:40 — the
  // readouts from the report, to the character.
  distanceMeters: 1213,
  elevationGainMeters: 108,
  // Empty on purpose: an empty route draws the map's "finding you" panel
  // instead of a tile layer, and no test reaches the network.
  route: const [],
  waypoints: const [],
  intentions: const [],
  placeName: 'Antipolo, Rizal',
);

Activity _reportedActivity() => Activity(
  id: _activityId,
  userId: _viewerId,
  type: ActivityType.walk,
  title: 'Morning walk in Antipolo',
  startedAt: DateTime(2026, 7, 27, 6, 4),
  duration: const Duration(minutes: 20, seconds: 13),
  distanceMeters: 1213,
  elevationGainMeters: 108,
  route: const [],
  placeName: 'Antipolo, Rizal',
);

UserProfile _profile() => UserProfile(
  id: _viewerId,
  displayName: 'Maria Reyes',
  handle: '@mariareyes',
  role: UserRole.member,
  status: MemberStatus.active,
  joinedAt: DateTime(2026, 1, 4),
  accentIndex: 1,
  parish: 'Our Lady of Peace and Good Voyage, Antipolo',
  bio: 'Walking the same four streets, most mornings.',
  followerCount: 1284,
  followingCount: 317,
  stats: const LifetimeStats(
    totalDistanceMeters: 1284000,
    totalDuration: Duration(hours: 312),
    activityCount: 481,
    streakDays: 26,
    intentionCount: 903,
  ),
);

/// The recording controller, parked on a finished draft.
class _FinishedRecording extends RecordingController {
  _FinishedRecording(this.draft);

  final ActivityDraft draft;

  @override
  RecordingState build() => RecordingState(
    status: RecordingStatus.finished,
    draft: draft,
    intentions: draft.intentions,
  );
}

/// A walk in progress, an hour in — the widest clock the live readouts carry,
/// with no route yet so the map draws its locating panel instead of tiles.
class _LiveRecording extends RecordingController {
  @override
  RecordingState build() => const RecordingState(
    status: RecordingStatus.recording,
    elapsed: Duration(hours: 1, minutes: 2, seconds: 3),
    distanceMeters: 4820,
    elevationGainMeters: 128,
  );
}

/// The same walk with scripture on and a verse on screen.
///
/// The arrival card sits over the map and the delivered list sits inside the
/// stats panel, so both have to survive the narrowest phone at the largest
/// text setting — the two places this feature could push a live recording off
/// the side of the screen.
class _LiveRecordingWithVerse extends RecordingController {
  static const _prompt = ScripturePrompt(
    id: 'sp_ps121',
    reference: 'Psalm 121:1-2',
    body: 'I will lift up my eyes to the hills. Where does my help come from? '
        'My help comes from the LORD, who made heaven and earth.',
    translation: 'WEBBE',
    category: DevotionalCategory.scriptureWalk,
  );

  static const _delivered = DeliveredPrompt(
    prompt: _prompt,
    elapsed: Duration(minutes: 12, seconds: 30),
    atMeters: 1213,
  );

  @override
  RecordingState build() => const RecordingState(
    status: RecordingStatus.recording,
    elapsed: Duration(hours: 1, minutes: 2, seconds: 3),
    distanceMeters: 4820,
    elevationGainMeters: 128,
    deliveredPrompts: [_delivered],
    currentPrompt: _delivered,
  );
}

class _StubActivityRepository implements ActivityRepository {
  const _StubActivityRepository();

  @override
  Future<List<Activity>> activitiesForUser(
    String userId, {
    ActivityType? type,
  }) async => [_reportedActivity()];

  @override
  Future<Activity> activityById(String id) async => _reportedActivity();

  @override
  Future<LocationReading> currentLocation() async =>
      throw UnsupportedError('no device position in a widget test');

  @override
  Future<List<PrayerIntention>> suggestedIntentions() async => const [];

  @override
  Future<Activity> saveDraft(String userId, ActivityDraft draft) async =>
      _reportedActivity();

  @override
  Future<void> deleteActivity(String id) async {}
}

class _StubProfileRepository implements ProfileRepository {
  const _StubProfileRepository();

  @override
  Future<UserProfile> profileById(String id) async => _profile();

  @override
  Future<UserProfile> updateProfile(String id, ProfileEdit edit) async =>
      _profile();
}

/// The app shell every case is pumped inside: the real theme, and one text
/// scale pinned for the whole tree.
MaterialApp _app(Widget home, double scale) => MaterialApp(
  theme: AppTheme.light(),
  builder: (context, inner) => MediaQuery.withClampedTextScaling(
    minScaleFactor: scale,
    maxScaleFactor: scale,
    child: inner!,
  ),
  home: home,
);

void main() {
  setUpAll(AppTypography.useBundledFonts);
  tearDownAll(AppTypography.useNetworkFonts);

  /// Pumps [root] on a screen [width] logical pixels wide and returns having
  /// given animations a moment to start.
  ///
  /// Deliberately not `pumpAndSettle`: the map's locating panel and the
  /// skeletons breathe forever by design, and settling would never return.
  Future<void> pumpAt(
    WidgetTester tester,
    Widget root, {
    required double width,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, width >= 700 ? 1000 : 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(root);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Runs [body] at every width and scale, naming the combination that fails.
  void forEverySize(
    String description,
    Future<void> Function(WidgetTester tester, double width, double scale) body,
  ) {
    for (final width in _widths) {
      for (final scale in _scales) {
        testWidgets('$description — ${width.round()}dp at ${scale}x', (
          tester,
        ) async {
          await body(tester, width, scale);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflowed at ${width.round()}dp, text scale $scale',
          );
        });
      }
    }
  }

  group('the summary screen', () {
    forEverySize('lays out without overflowing', (tester, width, scale) async {
      await pumpAt(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              () => _FinishedRecording(_reportedDraft()),
            ),
            activityRepositoryProvider.overrideWithValue(
              const _StubActivityRepository(),
            ),
            currentAuthUserIdProvider.overrideWith((ref) => _viewerId),
          ],
          child: _app(const ActivitySummaryScreen(), scale),
        ),
        width: width,
      );

      // The readouts from the bug report are all on screen, whole.
      expect(find.text('1.21'), findsOneWidget);
      expect(find.text('20:13'), findsOneWidget);
      expect(find.text('16:40'), findsOneWidget);
      expect(find.text('108'), findsOneWidget);
    });
  });

  group('the detail screen', () {
    forEverySize('lays out without overflowing', (tester, width, scale) async {
      await pumpAt(
        tester,
        ProviderScope(
          overrides: [
            activityRepositoryProvider.overrideWithValue(
              const _StubActivityRepository(),
            ),
            profileRepositoryProvider.overrideWithValue(
              const _StubProfileRepository(),
            ),
            socialRepositoryProvider.overrideWith(
              (ref) => FakeSocialRepository(),
            ),
            currentAuthUserIdProvider.overrideWith((ref) => _viewerId),
          ],
          child: _app(
            const ActivityDetailScreen(activityId: _activityId),
            scale,
          ),
        ),
        width: width,
      );
    });
  });

  group('the live screen', () {
    forEverySize('lays out without overflowing', (tester, width, scale) async {
      await pumpAt(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(_LiveRecording.new),
            activityRepositoryProvider.overrideWithValue(
              const _StubActivityRepository(),
            ),
            currentAuthUserIdProvider.overrideWith((ref) => _viewerId),
          ],
          child: _app(const LiveTrackingScreen(), scale),
        ),
        width: width,
      );

      // An hour-long walk's clock is the widest thing this row carries.
      expect(find.text('1:02:03'), findsOneWidget);
    });

    forEverySize('carries an arrived verse without overflowing', (
      tester,
      width,
      scale,
    ) async {
      await pumpAt(
        tester,
        ProviderScope(
          overrides: [
            recordingControllerProvider.overrideWith(
              _LiveRecordingWithVerse.new,
            ),
            activityRepositoryProvider.overrideWithValue(
              const _StubActivityRepository(),
            ),
            currentAuthUserIdProvider.overrideWith((ref) => _viewerId),
          ],
          child: _app(const LiveTrackingScreen(), scale),
        ),
        width: width,
      );

      // The card over the map and the row in the panel below it — the passage
      // is reachable in both places, so a verse missed on the card is not lost.
      expect(find.text('Psalm 121:1-2'), findsNWidgets(2));
      expect(find.text('WEBBE'), findsOneWidget);
    });
  });

  group('the profile header', () {
    forEverySize('lays out without overflowing', (tester, width, scale) async {
      await pumpAt(
        tester,
        ProviderScope(
          child: _app(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ProfileHeader(profile: _profile(), isSelf: true),
                  const SizedBox(height: 16),
                  LifetimeStatsPanel(stats: _profile().stats),
                ],
              ),
            ),
            scale,
          ),
        ),
        width: width,
      );
    });
  });

  group('StatStrip', () {
    /// Four tiles, as all three call sites use it.
    Widget strip() => const StatStrip(
      children: [
        StatTile(label: 'Distance', value: '1.21', unit: 'km'),
        StatTile(label: 'Time', value: '20:13'),
        StatTile(label: 'Pace', value: '16:40', unit: '/km'),
        StatTile(label: 'Climb', value: '108', unit: 'm'),
      ],
    );

    testWidgets('counts the dividers before choosing a single row', (
      tester,
    ) async {
      // The reporting device: 384dp less the screen's 16dp gutters. Four tiles
      // and three 24dp dividers leave 70dp each, which is under what a pace
      // readout needs — so this must wrap. The old heuristic divided 352 by 4,
      // got exactly 88, and took the row.
      await pumpAt(
        tester,
        _app(
          Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: strip()),
          ),
          1,
        ),
        width: 384,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
    });

    testWidgets('keeps the divided row where there is room for it', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _app(
          Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: strip()),
          ),
          1,
        ),
        width: 800,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(VerticalDivider), findsNWidgets(3));
    });

    testWidgets('a tile scales its figure rather than overflowing its slot', (
      tester,
    ) async {
      // Narrower than any tile wants, and with a value no strip would produce —
      // the last line of defence, exercised directly.
      await pumpAt(
        tester,
        _app(
          const Scaffold(
            body: Center(
              child: SizedBox(
                width: 56,
                child: StatTile(
                  label: 'Elapsed time',
                  value: '1:23:45',
                  unit: '/km',
                ),
              ),
            ),
          ),
          2,
        ),
        width: 320,
      );

      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(StatTile));
      expect(box.width, lessThanOrEqualTo(56));
    });

    testWidgets('the numeral keeps its tabular figures', (tester) async {
      await pumpAt(tester, _app(Scaffold(body: strip()), 1), width: 412);

      final value = tester.widget<Text>(find.text('16:40'));
      expect(
        value.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(value.style?.fontFamily, AppTypography.displayFamily);
    });
  });
}
