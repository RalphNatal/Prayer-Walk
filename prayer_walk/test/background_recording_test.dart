import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/data/recording_controller.dart';
import 'package:prayer_walk/src/features/activity/data/recording_journal.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/activity/domain/interrupted_recording.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recording that survives a pocket.
///
/// Three separate promises are checked here, and they fail in three different
/// ways:
///
///  * **The background configuration exists only inside a recording.** A
///    foreground service, a wake lock or a blue indicator held while nobody is
///    walking is a battery complaint and a store rejection, so the flag that
///    turns them on is asserted on every stream the recorder opens.
///  * **An interrupted walk comes back.** The journal is written as the walk
///    accumulates and read on the next launch; what goes in has to come out,
///    including the verses that were delivered on the way.
///  * **Resuming does not invent a leg.** The gap between where a walk died and
///    where it is picked up is not distance anybody covered, and the first fix
///    after a resume must not measure it.

class _FakeLocationService extends LocationService {
  _FakeLocationService({this.access = LocationAccess.granted});

  final LocationAccess access;
  final StreamController<LocationFix> fixes =
      StreamController<LocationFix>.broadcast();

  /// One entry per stream opened, holding what was asked for.
  final List<bool> backgroundRequests = [];

  /// Permission calls, in the order the recorder made them.
  final List<String> asked = [];

  int streamsClosed = 0;
  BackgroundLocationAccess held = BackgroundLocationAccess.denied;

  @override
  Future<LocationAccess> ensureAccess() async {
    asked.add('whenInUse');
    return access;
  }

  @override
  Future<bool> ensureNotificationAccess() async {
    asked.add('notification');
    return true;
  }

  @override
  Future<BackgroundLocationAccess> backgroundAccess() async => held;

  @override
  Future<BackgroundLocationAccess> requestBackgroundAccess() async {
    asked.add('background');
    held = BackgroundLocationAccess.granted;
    return held;
  }

  @override
  Stream<LocationFix> positionStream({bool background = false}) {
    backgroundRequests.add(background);
    late StreamController<LocationFix> out;
    StreamSubscription<LocationFix>? sub;
    out = StreamController<LocationFix>(
      onListen: () => sub = fixes.stream.listen(out.add, onError: out.addError),
      onCancel: () {
        streamsClosed++;
        return sub?.cancel();
      },
    );
    return out.stream;
  }
}

LocationFix fixAt(double lat, double lng, {double accuracy = 5}) => LocationFix(
  point: LatLng(lat, lng),
  accuracyMeters: accuracy,
  altitudeMeters: 10,
  timestamp: DateTime.now(),
);

const _lat = 14.5794;
const _lng = 121.0359;

ScripturePrompt _prompt(int i) => ScripturePrompt(
  id: 'sp_$i',
  reference: 'Psalm ${i + 1}:1',
  body: 'Verse number ${i + 1}.',
  translation: 'WEBBE',
  category: DevotionalCategory.stillness,
);

InterruptedRecording _walk({
  Duration elapsed = const Duration(minutes: 24),
  double distance = 1830,
  bool paused = false,
  Duration ago = const Duration(minutes: 3),
  List<LatLng>? route,
}) => InterruptedRecording(
  type: ActivityType.hike,
  startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
  lastSeenAt: DateTime.now().subtract(ago),
  elapsed: elapsed,
  distanceMeters: distance,
  elevationGainMeters: 42.5,
  route: route ?? const [LatLng(_lat, _lng), LatLng(14.5804, _lng)],
  waypoints: [
    Waypoint(
      id: 'w0',
      point: const LatLng(14.58, _lng),
      kind: WaypointKind.gratitude,
      label: 'Gave thanks',
      note: 'by the river',
      elapsed: const Duration(minutes: 6),
    ),
  ],
  intentions: [
    PrayerIntention(
      id: 'i0',
      text: 'For the parish',
      category: PrayerCategory.community,
      createdAt: DateTime.now(),
    ),
  ],
  deliveredPrompts: [
    DeliveredPrompt(
      prompt: _prompt(0),
      elapsed: const Duration(minutes: 9),
      atMeters: 640,
    ),
  ],
  scripture: const ScriptureSettings(
    cadence: ScriptureCadence.spacious,
    category: DevotionalCategory.lament,
    sound: false,
    voice: true,
  ),
  devotionalTitle: 'A quiet mile',
  devotionalCategory: DevotionalCategory.lament,
  wasPaused: paused,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocationService service;
  late ProviderContainer container;

  RecordingController controller() =>
      container.read(recordingControllerProvider.notifier);
  RecordingState state() => container.read(recordingControllerProvider);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = _FakeLocationService();
    container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
  });

  Future<void> emit(LocationFix fix) async {
    service.fixes.add(fix);
    await Future<void>.delayed(Duration.zero);
  }

  group('background is only ever on inside a recording', () {
    test('a recording asks for it', () async {
      await controller().start();
      expect(service.backgroundRequests, [true]);
    });

    test('finishing takes it away again', () async {
      await controller().start();
      await emit(fixAt(_lat, _lng));
      controller().finish();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 1);
    });

    test('discarding takes it away again', () async {
      await controller().start();
      controller().discard();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 1);
    });

    test('a pause keeps it, deliberately', () async {
      // Dropping the service on every prayer stop would cost the GNSS lock,
      // and Android 12+ would not let a backgrounded app start it again.
      await controller().start();
      controller().pause();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 0);
      expect(service.backgroundRequests, hasLength(1));
    });

    test('resuming a walk opens exactly one stream, never two', () async {
      await controller().start();
      controller().pause();
      controller().resume();
      await Future<void>.delayed(Duration.zero);

      expect(service.backgroundRequests, hasLength(1));
    });
  });

  group('the second permission step', () {
    test('background is asked for after when-in-use, never before', () async {
      await controller().start();

      final whenInUse = service.asked.indexOf('whenInUse');
      final background = service.asked.indexOf('background');
      expect(whenInUse, isNonNegative);
      expect(background, greaterThan(whenInUse));
    });

    test('a refused walk is never asked for background location', () async {
      container.dispose();
      service = _FakeLocationService(access: LocationAccess.denied);
      container = ProviderContainer(
        overrides: [locationServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await controller().start();

      expect(service.asked, ['whenInUse']);
      expect(service.backgroundRequests, isEmpty);
    });

    test('the second walk does not ask again', () async {
      await controller().start();
      controller().discard();
      await controller().start();

      expect(service.asked.where((a) => a == 'background'), hasLength(1));
    });
  });

  group('the journal', () {
    test('round-trips a walk through disk', () async {
      final written = _walk();
      await RecordingJournal().saveNow(written);

      // A fresh instance, so nothing can be answered from memory.
      final read = await RecordingJournal().read();

      expect(read, isNotNull);
      expect(read!.type, ActivityType.hike);
      expect(read.distanceMeters, closeTo(1830, 0.001));
      expect(read.elevationGainMeters, closeTo(42.5, 0.001));
      expect(read.elapsed, const Duration(minutes: 24));
      expect(read.route, hasLength(2));
      expect(read.route.first.latitude, closeTo(_lat, 0.000001));
      expect(read.waypoints.single.kind, WaypointKind.gratitude);
      expect(read.waypoints.single.note, 'by the river');
      expect(read.intentions.single.text, 'For the parish');
      expect(read.devotionalTitle, 'A quiet mile');
      expect(read.devotionalCategory, DevotionalCategory.lament);
    });

    test('the verses that were given come back with it', () async {
      await RecordingJournal().saveNow(_walk());
      final read = await RecordingJournal().read();

      final delivered = read!.deliveredPrompts.single;
      expect(delivered.prompt.id, 'sp_0');
      expect(delivered.prompt.reference, 'Psalm 1:1');
      expect(delivered.prompt.translation, 'WEBBE');
      expect(delivered.atMeters, closeTo(640, 0.001));
    });

    test('the walk was paused, and comes back paused', () async {
      await RecordingJournal().saveNow(_walk(paused: true));
      expect((await RecordingJournal().read())!.wasPaused, isTrue);
    });

    test('this walk\'s scripture settings come back, not the default', () async {
      await RecordingJournal().saveNow(_walk());
      final scripture = (await RecordingJournal().read())!.scripture;

      expect(scripture.cadence.intervalMeters, 800);
      expect(scripture.category, DevotionalCategory.lament);
      expect(scripture.sound, isFalse);
      expect(scripture.voice, isTrue);
    });

    test('a button press with nothing behind it is not offered back', () async {
      await RecordingJournal().saveNow(
        _walk(elapsed: Duration.zero, distance: 0, route: const []),
      );
      expect(await RecordingJournal().read(), isNull);
    });

    test('nonsense on disk reads as nothing rather than throwing', () async {
      SharedPreferences.setMockInitialValues({
        'recording.inProgress.v1': 'not json at all',
      });
      expect(await RecordingJournal().read(), isNull);
    });

    test('clearing it means there is nothing to offer', () async {
      final journal = RecordingJournal();
      await journal.saveNow(_walk());
      await journal.clear();
      expect(await RecordingJournal().read(), isNull);
    });
  });

  group('a walk in progress is written as it happens', () {
    test('a marked prayer reaches disk without waiting', () async {
      await controller().start();
      await emit(fixAt(_lat, _lng));
      controller().dropWaypoint(WaypointKind.stillness);
      await Future<void>.delayed(Duration.zero);

      final journalled = await RecordingJournal().read();
      expect(journalled, isNotNull);
      expect(journalled!.waypoints.single.kind, WaypointKind.stillness);
    });

    test('a saved walk leaves nothing behind to be offered', () async {
      await controller().start();
      await emit(fixAt(_lat, _lng));
      controller().finish();
      // `finish` deliberately keeps the journal — the draft on the summary
      // screen is the next thing that can be lost.
      await Future<void>.delayed(Duration.zero);
      expect(await RecordingJournal().read(), isNotNull);

      controller().discard();
      await Future<void>.delayed(Duration.zero);
      expect(await RecordingJournal().read(), isNull);
    });
  });

  group('picking a lost walk back up', () {
    test('every total is restored', () async {
      await controller().resumeInterrupted(_walk());

      expect(state().status, RecordingStatus.recording);
      expect(state().type, ActivityType.hike);
      expect(state().distanceMeters, closeTo(1830, 0.001));
      expect(state().elevationGainMeters, closeTo(42.5, 0.001));
      expect(state().elapsed, const Duration(minutes: 24));
      expect(state().route, hasLength(2));
      expect(state().waypoints, hasLength(1));
      expect(state().deliveredPrompts, hasLength(1));
      expect(state().intentions.single.text, 'For the parish');
    });

    test('a walk paused when the app died resumes paused', () async {
      await controller().resumeInterrupted(_walk(paused: true));
      expect(state().status, RecordingStatus.paused);
    });

    test('the gap is not measured as distance', () async {
      await controller().resumeInterrupted(_walk());
      final restored = state().distanceMeters;

      // Where the walker actually is now: a long way from where the walk
      // stopped. This is the phantom leg, and it must not be counted.
      await emit(fixAt(14.6200, 121.0700));
      expect(state().distanceMeters, closeTo(restored, 0.001));

      // The next fix is real walking, and is.
      await emit(fixAt(14.6205, 121.0700));
      expect(state().distanceMeters, greaterThan(restored));
      expect(state().distanceMeters, lessThan(restored + 100));
    });

    test('it warms up again, because the device has been asleep', () async {
      await controller().resumeInterrupted(_walk());
      expect(state().warmingUp, isTrue);
    });

    test('it records in the background like any other walk', () async {
      await controller().resumeInterrupted(_walk());
      expect(service.backgroundRequests, [true]);
    });
  });

  group('keeping a lost walk without resuming it', () {
    test('it becomes a draft with its totals intact', () async {
      controller().keepInterrupted(_walk());

      expect(state().status, RecordingStatus.finished);
      final draft = state().draft;
      expect(draft, isNotNull);
      expect(draft!.distanceMeters, closeTo(1830, 0.001));
      expect(draft.duration, const Duration(minutes: 24));
      expect(draft.route, hasLength(2));
      expect(draft.waypoints, hasLength(1));
      expect(draft.type, ActivityType.hike);
      expect(draft.title, contains('hike'));
    });

    test('nothing starts recording', () async {
      controller().keepInterrupted(_walk());
      expect(service.backgroundRequests, isEmpty);
      expect(state().isLive, isFalse);
    });
  });

  group('what counts as worth offering', () {
    test('a traced walk always is, however short', () {
      expect(
        _walk(elapsed: Duration.zero, distance: 0).isWorthOffering,
        isTrue,
      );
    });

    test('half a minute on the clock is, even with no route', () {
      expect(
        _walk(
          elapsed: const Duration(seconds: 45),
          route: const [],
        ).isWorthOffering,
        isTrue,
      );
    });

    test('a walk lost this morning is offered but not resumable', () {
      final old = _walk(ago: const Duration(hours: 9));
      expect(old.isWorthOffering, isTrue);
      expect(old.isTooOldToResume, isTrue);
    });

    test('a walk lost minutes ago is resumable', () {
      expect(_walk().isTooOldToResume, isFalse);
    });
  });
}
