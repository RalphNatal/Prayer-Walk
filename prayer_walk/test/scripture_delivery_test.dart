import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:prayer_walk/src/features/activity/data/activity_row_mapper.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/data/recording_controller.dart';
import 'package:prayer_walk/src/features/activity/data/step_cadence_trigger.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/activity/domain/cadence_trigger.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_history_controller.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_prompt_store.dart';
import 'package:prayer_walk/src/features/scripture/data/scripture_providers.dart';
import 'package:prayer_walk/src/features/scripture/data/supabase_scripture_repository.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_library.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_repository.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_submission.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scripture on the trail, from the recorder's side.
///
/// Everything here is asserted against [RecordingController] rather than the
/// screen, because the controller is where the promises live: a verse arrives
/// at the first interval and not at the start line, never while paused, never
/// twice on one walk, and always leaves a waypoint behind that survives the
/// save.
///
/// The chime and the voice are asserted here too, through a silent stand-in for
/// [ScriptureAnnouncer]. They used to be the live screen's business, which is
/// why they used to be out of scope — and also why a verse arriving with the
/// app on another tab or the screen locked went out in silence. Announcing is
/// the recorder's job now, so a test with no speaker is exactly the thing that
/// can check it happens.

/// A location service driven by the test.
class _FakeLocationService extends LocationService {
  final StreamController<LocationFix> controller =
      StreamController<LocationFix>.broadcast();

  /// Whether each opened stream asked for background delivery.
  final List<bool> backgroundRequests = [];

  @override
  Future<LocationAccess> ensureAccess() async => LocationAccess.granted;

  @override
  Future<bool> ensureNotificationAccess() async => true;

  @override
  Future<BackgroundLocationAccess> backgroundAccess() async =>
      BackgroundLocationAccess.granted;

  @override
  Stream<LocationFix> positionStream({bool background = false}) {
    backgroundRequests.add(background);
    return controller.stream;
  }
}

/// An announcer with no speaker, no engine and no plugins — it only remembers
/// what it was asked to say.
class _SilentAnnouncer extends ScriptureAnnouncer {
  final List<ScripturePrompt> spoken = [];
  final List<({bool sound, bool voice})> channels = [];
  int silenced = 0;

  @override
  Future<void> announce(
    ScripturePrompt prompt, {
    required bool sound,
    required bool voice,
    FlutterView? view,
  }) async {
    spoken.add(prompt);
    channels.add((sound: sound, voice: voice));
  }

  @override
  Future<void> silence() async => silenced++;

  @override
  void dispose() {}
}

/// A fixed library, with no network under it.
class _StubScriptureRepository implements ScriptureRepository {
  const _StubScriptureRepository(this.prompts);

  final List<ScripturePrompt> prompts;

  @override
  Future<List<ScripturePrompt>> publishedPrompts({
    DevotionalCategory? category,
  }) async => (await publishedLibrary(category: category)).prompts;

  @override
  Future<ScriptureLibrary> publishedLibrary({
    DevotionalCategory? category,
  }) async {
    final available = category == null
        ? prompts
        : prompts.where((p) => p.category == category).toList();
    return ScriptureLibrary(
      prompts: available,
      source: ScriptureLibrarySource.cache,
      requested: BibleTranslation.fallback,
      available: available,
    );
  }

  @override
  Future<List<ScripturePrompt>> allPrompts() async => prompts;

  @override
  Future<ScripturePrompt> savePrompt(ScripturePromptDraft draft) async =>
      throw UnimplementedError();

  @override
  Future<ScripturePrompt> setPublished(String id, {required bool published}) =>
      throw UnimplementedError();

  @override
  Future<void> deletePrompt(String id) async {}

  // Curation and the submissions queue are not what this test is about: it
  // exercises delivery on a walk, which reads `publishedPrompts` and nothing
  // else. Unimplemented is the honest stub — a silent empty list here would let
  // a future test pass while calling something that never happened.
  @override
  Future<void> submitPrompt(ScriptureSubmissionDraft draft) =>
      throw UnimplementedError();

  @override
  Future<List<ScriptureSubmission>> mySubmissions() =>
      throw UnimplementedError();

  @override
  Future<List<ScriptureSubmission>> submissions({SubmissionStatus? status}) =>
      throw UnimplementedError();

  @override
  Future<void> reviewSubmission(
    String id, {
    required SubmissionStatus outcome,
    String reason = '',
  }) => throw UnimplementedError();
}

/// A step trigger that reports the hardware missing, so the fallback path can
/// be exercised without a pedometer.
class _AbsentStepTrigger implements CadenceTrigger {
  @override
  Future<CadenceReadiness> prepare() async => CadenceReadiness.unavailable;

  @override
  Stream<void> get due => const Stream<void>.empty();

  @override
  bool isDue(double distanceMeters) => false;

  @override
  void reset() {}

  @override
  void dispose() {}
}

LocationFix fixAt(double lat, double lng, {double accuracy = 5}) => LocationFix(
  point: LatLng(lat, lng),
  accuracyMeters: accuracy,
  altitudeMeters: 10,
  timestamp: DateTime.now(),
);

List<ScripturePrompt> _library([int count = 6]) => [
  for (var i = 0; i < count; i++)
    ScripturePrompt(
      id: 'sp_$i',
      reference: 'Psalm ${i + 1}:1',
      body: 'Verse number ${i + 1}.',
      translation: 'WEBBE',
      category: i.isEven
          ? DevotionalCategory.stillness
          : DevotionalCategory.gratitude,
    ),
];

/// Roughly 445 m of latitude — one step past the 400 m default interval.
const _step = 0.004;
const _startLat = 14.5794;
const _lng = 121.0359;

void main() {
  // `shared_preferences` and the bundled asset both need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocationService service;
  late _SilentAnnouncer announcer;
  late ProviderContainer container;

  RecordingController controller() =>
      container.read(recordingControllerProvider.notifier);
  RecordingState state() => container.read(recordingControllerProvider);

  void setUpWith({
    ScriptureRepository? repository,
    CadenceTrigger Function(int)? stepTrigger,
  }) {
    SharedPreferences.setMockInitialValues({});
    service = _FakeLocationService();
    announcer = _SilentAnnouncer();
    container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
        scriptureAnnouncerProvider.overrideWithValue(announcer),
        scriptureRepositoryProvider.overrideWithValue(
          repository ?? _StubScriptureRepository(_library()),
        ),
        if (stepTrigger != null)
          stepTriggerBuilderProvider.overrideWithValue(stepTrigger),
      ],
    );
    addTearDown(container.dispose);
  }

  setUp(setUpWith);

  Future<void> emit(LocationFix fix) async {
    service.controller.add(fix);
    await Future<void>.delayed(Duration.zero);
  }

  /// Starts a walk and waits for the verse library to land, so the tests are
  /// about cadence rather than about a race with a future.
  Future<void> startWalk() async {
    await controller().start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  /// The [n]th fix of the walk, each one interval further north than the last.
  LocationFix leg(int n) => fixAt(_startLat + _step * n, _lng);

  group('arrival', () {
    test('nothing arrives at the start line', () async {
      await startWalk();
      await emit(leg(0));

      expect(state().deliveredPrompts, isEmpty);
      expect(state().waypoints, isEmpty);
      expect(state().currentPrompt, isNull);
    });

    test('the first verse arrives at the first interval', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1)); // ~445 m — past the 400 m default

      expect(state().deliveredPrompts, hasLength(1));
      expect(state().currentPrompt, isNotNull);
      expect(state().distanceMeters, greaterThan(400));
    });

    test('the verse is spoken with no screen involved at all', () async {
      // The point of this test is what is *not* in it: no widget, no
      // `pumpWidget`, no live screen. A phone in a pocket has no built screen
      // either, and it used to be the screen doing the announcing — so a verse
      // arriving with the app on another tab, or with the route torn down
      // behind a lock screen, went out in silence.
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      expect(announcer.spoken, hasLength(1));
      expect(announcer.spoken.single.id, state().deliveredPrompts.single.prompt.id);
      expect(announcer.channels.single.sound, isTrue);
      expect(announcer.channels.single.voice, isTrue);
    });

    test('a muted walk delivers the verse and says nothing', () async {
      await startWalk();
      controller().setScriptureMuted(true);
      await emit(leg(0));
      await emit(leg(1));

      expect(state().deliveredPrompts, hasLength(1), reason: 'still arrives');
      expect(announcer.channels.single.sound, isFalse);
      expect(announcer.channels.single.voice, isFalse);
    });

    test('muting mid-sentence stops the voice', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));
      final before = announcer.silenced;

      controller().setScriptureMuted(true);
      expect(announcer.silenced, greaterThan(before));
    });

    test('pausing stops the voice wherever the walker is', () async {
      await startWalk();
      await emit(leg(0));
      final before = announcer.silenced;

      controller().pause();
      expect(announcer.silenced, greaterThan(before));
    });

    test('finishing stops the voice', () async {
      await startWalk();
      await emit(leg(0));
      final before = announcer.silenced;

      controller().finish();
      expect(announcer.silenced, greaterThan(before));
    });

    test('each verse drops a scripture waypoint where it landed', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      final waypoint = state().waypoints.single;
      final prompt = state().deliveredPrompts.single.prompt;

      expect(waypoint.kind, WaypointKind.scripture);
      expect(waypoint.label, prompt.reference);
      expect(waypoint.note, prompt.body);
      expect(
        waypoint.point,
        state().lastPoint,
        reason: 'the marker belongs where the verse reached the walker',
      );
    });

    test('a single large jump delivers exactly one verse', () async {
      await startWalk();
      await emit(leg(0));
      // Three kilometres in one fix — seven intervals crossed at once.
      await emit(fixAt(_startLat + 0.027, _lng));

      expect(state().distanceMeters, greaterThan(2500));
      expect(
        state().deliveredPrompts,
        hasLength(1),
        reason: 'a bad fix must not empty the library into the walker',
      );
    });

    test('nothing arrives while the recording is paused', () async {
      await startWalk();
      await emit(leg(0));
      controller().pause();

      await emit(leg(1));
      await emit(leg(2));

      expect(state().deliveredPrompts, isEmpty);
      expect(state().waypoints, isEmpty);
    });

    test('resuming picks up from the right threshold', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1)); // first verse at ~445 m
      controller().pause();
      controller().resume();

      // The first fix after a resume starts a fresh segment and adds no
      // distance, so the walk is still at ~445 m and owes nothing.
      await emit(leg(2));
      expect(state().deliveredPrompts, hasLength(1));

      // Now past 800 m of *measured* distance, and the next verse is owed.
      await emit(leg(3));
      expect(state().deliveredPrompts, hasLength(2));
    });

    test('nothing arrives while the signal is still warming up', () async {
      await startWalk();
      expect(state().warmingUp, isTrue);

      // Coarse fixes, far apart. None of them is plotted, so none of them may
      // deliver a verse either.
      await emit(fixAt(_startLat, _lng, accuracy: 22));
      await emit(fixAt(_startLat + 0.02, _lng, accuracy: 22));
      await emit(fixAt(_startLat + 0.04, _lng, accuracy: 22));

      expect(state().warmingUp, isTrue);
      expect(state().deliveredPrompts, isEmpty);
      expect(state().waypoints, isEmpty);
    });

    test('an empty library costs verses, not the walk', () async {
      setUpWith(repository: const _StubScriptureRepository([]));
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      expect(state().deliveredPrompts, isEmpty);
      expect(state().route, hasLength(2), reason: 'the walk is unaffected');
      expect(state().distanceMeters, greaterThan(400));
    });

    test('scripture switched off delivers nothing', () async {
      container.read(scriptureSettingsProvider.notifier).setEnabled(false);
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));
      await emit(leg(2));

      expect(state().deliveredPrompts, isEmpty);
      expect(state().waypoints, isEmpty);
    });
  });

  group('the draw', () {
    test('no verse repeats until the library is exhausted', () async {
      setUpWith(repository: _StubScriptureRepository(_library(4)));
      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 4; n++) {
        await emit(leg(n));
      }

      final drawn = state().deliveredPrompts.map((d) => d.prompt.id).toList();
      expect(drawn, hasLength(4));
      expect(
        drawn.toSet(),
        hasLength(4),
        reason: 'four draws from four verses must be four different verses',
      );
    });

    test('an exhausted library reshuffles rather than going quiet', () async {
      setUpWith(repository: _StubScriptureRepository(_library(3)));
      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 6; n++) {
        await emit(leg(n));
      }

      final drawn = state().deliveredPrompts.map((d) => d.prompt.id).toList();
      expect(drawn, hasLength(6));
      expect(drawn.take(3).toSet(), hasLength(3));
      expect(drawn.skip(3).take(3).toSet(), hasLength(3));
      expect(
        drawn[2],
        isNot(drawn[3]),
        reason: 'a reshuffle must not open on the verse that just went by',
      );
    });

    test('ten consecutive walks repeat nothing while anything is unseen', () async {
      // The complaint this whole change answers, asserted end to end rather
      // than reasoned about. Ten walks of six verses is sixty draws; the
      // library holds seventy, so nothing should come round twice.
      //
      // Before delivery history this failed on walk two — each walk reshuffled
      // the whole library from nothing, so two draws of six from seventy
      // collided about forty per cent of the time, and by walk ten a repeat was
      // a certainty.
      setUpWith(repository: _StubScriptureRepository(_library(70)));

      final everything = <String>[];
      for (var walk = 0; walk < 10; walk++) {
        await startWalk();
        await emit(leg(0));
        for (var n = 1; n <= 6; n++) {
          await emit(leg(n));
        }
        everything.addAll(state().deliveredPrompts.map((d) => d.prompt.id));
        // Ends the walk exactly as discarding one does, which is what clears
        // the queue and pushes the deliveries to the mirror.
        controller().discard();
        await Future<void>.delayed(Duration.zero);
      }

      expect(everything, hasLength(60));
      expect(
        everything.toSet(),
        hasLength(60),
        reason: 'sixty draws from a library of seventy, with a record of what '
            'has already been given, must be sixty different passages',
      );
    });

    test('a passage delivered yesterday does not come back today', () async {
      final prompts = _library(20);
      setUpWith(repository: _StubScriptureRepository(prompts));

      // Yesterday's walk, written straight into the record rather than walked,
      // so the assertion is about selection and not about the clock.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final history = container.read(scriptureHistoryProvider.notifier);
      for (var i = 0; i < 6; i++) {
        history.record('sp_$i', at: yesterday);
      }

      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 6; n++) {
        await emit(leg(n));
      }

      final drawn = state().deliveredPrompts.map((d) => d.prompt.id).toSet();
      expect(drawn, hasLength(6));
      expect(
        drawn.intersection({for (var i = 0; i < 6; i++) 'sp_$i'}),
        isEmpty,
        reason: 'fourteen passages remain unseen — none of yesterday\'s six '
            'should be reached',
      );
    });

    test('what a walk delivered is remembered', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      final delivered = state().deliveredPrompts.single.prompt.id;
      expect(
        container.read(scriptureHistoryProvider).hasSeen(delivered),
        isTrue,
      );
    });

    test('history that cannot reach the server still governs the walk', () async {
      // Supabase is not initialised in a test, so every mirror call fails
      // exactly as it does on a walk with no signal. The walk must be
      // unaffected — and the *next* walk must still know what this one gave.
      setUpWith(repository: _StubScriptureRepository(_library(20)));

      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 4; n++) {
        await emit(leg(n));
      }
      final firstWalk = state().deliveredPrompts.map((d) => d.prompt.id).toSet();
      expect(firstWalk, hasLength(4));

      controller().discard();
      await Future<void>.delayed(Duration.zero);

      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 4; n++) {
        await emit(leg(n));
      }
      final secondWalk = state().deliveredPrompts.map((d) => d.prompt.id).toSet();

      expect(secondWalk, hasLength(4));
      expect(
        firstWalk.intersection(secondWalk),
        isEmpty,
        reason: 'a failed mirror write must not cost the local record',
      );
    });

    test('a chosen theme is worked through before anything else', () async {
      setUpWith(repository: _StubScriptureRepository(_library(6)));
      container
          .read(scriptureSettingsProvider.notifier)
          .setCategory(DevotionalCategory.gratitude);
      await startWalk();
      await emit(leg(0));
      for (var n = 1; n <= 3; n++) {
        await emit(leg(n));
      }

      final drawn = state().deliveredPrompts.map((d) => d.prompt).toList();
      // Three of the six are gratitude, so the first three draws are all of
      // them before the pool reaches anything else.
      expect(
        drawn.take(3).every((p) => p.category == DevotionalCategory.gratitude),
        isTrue,
      );
    });

    test('a devotional walk prefers its own collection', () async {
      setUpWith(repository: _StubScriptureRepository(_library(6)));
      controller().carryDevotional(
        'Out of the depths',
        category: DevotionalCategory.stillness,
      );
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      expect(
        state().deliveredPrompts.single.prompt.category,
        DevotionalCategory.stillness,
      );
    });
  });

  group('the mute control', () {
    test('mutes both channels for this walk only', () async {
      await startWalk();
      expect(state().scriptureMuted, isFalse);

      controller().setScriptureMuted(true);

      expect(state().scriptureMuted, isTrue);
      expect(state().scripture.sound, isFalse);
      expect(state().scripture.voice, isFalse);
      expect(
        container.read(scriptureSettingsProvider).sound,
        isTrue,
        reason: 'muting one walk is not deciding never to hear another',
      );
    });
  });

  /// Step cadence, driven by a scripted pedometer and starved of GPS.
  ///
  /// This is the group that answers the device report. The recorder used to ask
  /// its trigger one question in one place — after an accepted fix had moved
  /// the distance — so a step trigger was paced, in practice, by the sensor it
  /// deliberately does not use. On a prayer walk that is precisely the wrong
  /// coupling: slow enough to fall under the 3 m accumulation floor, under tree
  /// cover wide enough to fail the 25 m accuracy gate, and the verses stopped.
  ///
  /// So every test here withholds the thing the old path depended on.
  group('step cadence', () {
    late StreamController<int> sensor;

    /// The reading the device happens to be at when the walk begins. Android
    /// counts from the last boot, so this is a number to subtract, not a walk.
    const boot = 51200;

    /// Starts a walk on step cadence with [sensor] standing in for the
    /// pedometer, and waits for the trigger to be swapped in for the interim
    /// distance one.
    Future<void> startStepWalk({int intervalSteps = 500}) async {
      sensor = StreamController<int>();
      addTearDown(sensor.close);
      setUpWith(
        stepTrigger: (interval) =>
            StepCadenceTrigger(intervalSteps: interval, source: sensor.stream),
      );
      container
          .read(scriptureSettingsProvider.notifier)
          .setCadence(
            ScriptureCadence(
              source: CadenceSource.steps,
              intervalSteps: intervalSteps,
              // Far enough out that the interim distance trigger cannot be the
              // thing delivering anything these tests assert on.
              intervalMeters: 100000,
            ),
          );

      await controller().start();
      // The baseline the sensor probe is waiting on.
      sensor.add(boot);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    /// Walks [steps] more, and lets the push signal reach the recorder.
    Future<void> step(int steps) async {
      sensor.add(boot + steps);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('verses arrive on steps alone, with no fix ever moving the walk', () async {
      await startStepWalk();
      // One fix, to close the warm-up gate and give the markers a place. After
      // this the position stream says nothing at all for the rest of the walk —
      // the GPS gap that used to make the feature silent.
      await emit(leg(0));
      expect(state().deliveredPrompts, isEmpty, reason: 'not at the start line');

      await step(499);
      expect(state().deliveredPrompts, isEmpty, reason: 'inside the interval');

      await step(500);
      expect(state().deliveredPrompts, hasLength(1));

      await step(1000);
      await step(1500);
      await step(2000);

      expect(
        state().deliveredPrompts,
        hasLength(4),
        reason: 'one verse at each step threshold, on zero metres of GPS',
      );
      expect(
        state().distanceMeters,
        0,
        reason: 'the walk never moved as far as the recorder is concerned — '
            'which is the entire point of the test',
      );
      expect(state().waypoints, hasLength(4));
    });

    test('rejected and sub-floor fixes do not hold the verses up', () async {
      await startStepWalk();
      await emit(leg(0));

      // Everything the accepted-position handler throws away: fixes wider than
      // the accuracy gate, and fixes too close to the last one to count.
      await emit(fixAt(_startLat + 0.004, _lng, accuracy: 40));
      await emit(fixAt(_startLat + 0.000001, _lng));

      await step(500);
      await step(1000);

      expect(state().deliveredPrompts, hasLength(2));
    });

    test('a batched delivery of several intervals is exactly one verse', () async {
      await startStepWalk();
      await emit(leg(0));

      // The sensor went quiet — a doze window, a batching handset — and then
      // handed over four intervals in one sample.
      await step(2100);

      expect(
        state().deliveredPrompts,
        hasLength(1),
        reason: 'a late batch is one verse, not a backlog emptied into the walker',
      );

      // ...and the next one is owed at the next threshold above where the walk
      // actually is, not back at 1000.
      await step(2400);
      expect(state().deliveredPrompts, hasLength(1));
      await step(2500);
      expect(state().deliveredPrompts, hasLength(2));
    });

    test('a threshold crossed before the walk has a place is held, not lost', () async {
      await startStepWalk();
      // No fix at all yet: nothing is plotted, so there is nowhere truthful to
      // put a marker. The verse must not be spent on nowhere.
      await step(500);
      await step(1200);

      expect(state().deliveredPrompts, isEmpty);
      expect(state().waypoints, isEmpty);

      // The signal arrives. What was held is owed, and arrives once.
      await emit(leg(0));

      expect(
        state().deliveredPrompts,
        hasLength(1),
        reason: 'the walker earned it before the GPS caught up',
      );
      expect(state().waypoints.single.point, state().lastPoint);
    });

    test('nothing arrives on steps while the walk is paused', () async {
      await startStepWalk();
      await emit(leg(0));
      controller().pause();

      await step(500);
      await step(1000);

      expect(state().deliveredPrompts, isEmpty);

      // ...and what was owed on the far side of the pause was held rather than
      // eaten, because a suppressed evaluation never consults the trigger.
      controller().resume();
      expect(state().deliveredPrompts, hasLength(1));
    });

    test('a custom interval is the one the walk is actually paced by', () async {
      // The setting used to be stored and ignored: the panel wrote metres only,
      // so a walker on step cadence kept whichever step interval the last
      // preset had left behind.
      await startStepWalk(intervalSteps: 200);
      await emit(leg(0));

      await step(200);
      await step(400);

      expect(state().deliveredPrompts, hasLength(2));
    });

    test('an absent sensor falls back to distance and says so', () async {
      setUpWith(stepTrigger: (_) => _AbsentStepTrigger());
      container
          .read(scriptureSettingsProvider.notifier)
          .setSource(CadenceSource.steps);

      await startWalk();
      expect(state().scriptureFellBackToDistance, isTrue);

      // ...and the walk still delivers, on the distance the step interval maps
      // to (500 steps ≈ 400 m).
      await emit(leg(0));
      await emit(leg(1));
      expect(state().deliveredPrompts, hasLength(1));
    });

    test('a refused permission is a fallback, not a silent walk', () async {
      // What `ACTIVITY_RECOGNITION` denial looks like from the recorder's side:
      // the trigger reports itself unavailable before any sensor is reached.
      setUpWith(stepTrigger: (_) => _AbsentStepTrigger());
      container
          .read(scriptureSettingsProvider.notifier)
          .setSource(CadenceSource.steps);

      await startWalk();

      expect(
        state().scriptureFellBackToDistance,
        isTrue,
        reason: 'the flag is what the live screen says its one sentence from',
      );
      expect(state().scripture.enabled, isTrue);
    });
  });

  group('the saved walk', () {
    test('scripture waypoints reach the draft and survive a round trip', () async {
      await startWalk();
      await emit(leg(0));
      await emit(leg(1));
      controller().dropWaypoint(WaypointKind.gratitude, label: 'The bend');
      controller().finish();

      final draft = state().draft!;
      final verse = draft.waypoints.firstWhere(
        (w) => w.kind == WaypointKind.scripture,
      );
      expect(draft.waypoints, hasLength(2));

      // Through the same JSONB shape `saveDraft` writes and `activityFromRow`
      // reads back — no schema change, no separate marker type.
      final row = <String, dynamic>{
        'id': 'a_1',
        'user_id': 'u_1',
        'type': 'walk',
        'title': draft.title,
        'started_at': draft.startedAt.toUtc().toIso8601String(),
        'duration_seconds': draft.duration.inSeconds,
        'distance_meters': draft.distanceMeters,
        'elevation_gain_meters': draft.elevationGainMeters,
        'route': encodeRoute(draft.route),
        'waypoints': encodeWaypoints(draft.waypoints),
        'intentions': encodeIntentions(draft.intentions),
        'note': '',
        'place_name': null,
      };

      final reopened = activityFromRow(row);
      final restored = reopened.waypoints.firstWhere(
        (w) => w.kind == WaypointKind.scripture,
      );

      expect(reopened.waypoints, hasLength(2));
      expect(restored.label, verse.label);
      expect(restored.note, verse.note, reason: 'the verse text comes back');
      expect(restored.point.latitude, closeTo(verse.point.latitude, 1e-9));
      expect(restored.elapsed, verse.elapsed);
    });
  });

  group('offline', () {
    test('a failed sync falls back to the cached library', () async {
      SharedPreferences.setMockInitialValues({});
      const store = ScripturePromptStore();
      await store.writeCache(_library(3));

      // Supabase is not initialized in a test, so the fetch inside the
      // repository fails exactly as it does on a walk with no signal.
      const repository = SupabaseScriptureRepository(store);
      final prompts = await repository.publishedPrompts();

      expect(prompts, hasLength(3));
      expect(prompts.first.reference, 'Psalm 1:1');
      expect(prompts.first.translation, 'WEBBE');
    });

    test('with no cache either, the bundled set carries the walk', () async {
      SharedPreferences.setMockInitialValues({});

      const repository = SupabaseScriptureRepository();
      final prompts = await repository.publishedPrompts();

      expect(
        prompts.length,
        greaterThanOrEqualTo(40),
        reason: 'a long walk should not run out on the shipped set alone',
      );
      expect(
        prompts.every((p) => p.reference.isNotEmpty && p.body.isNotEmpty),
        isTrue,
      );
      // The licensing guarantee, asserted rather than assumed: nothing
      // copyrighted is bundled.
      expect(
        prompts.map((p) => p.translation).toSet(),
        everyElement(anyOf('WEBBE', '')),
      );
    });

    test('a walk with the network down still delivers verses', () async {
      SharedPreferences.setMockInitialValues({});
      service = _FakeLocationService();
      announcer = _SilentAnnouncer();
      container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(service),
          scriptureAnnouncerProvider.overrideWithValue(announcer),
          // The real repository, with no Supabase behind it.
          scriptureRepositoryProvider.overrideWithValue(
            const SupabaseScriptureRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await startWalk();
      await emit(leg(0));
      await emit(leg(1));

      expect(state().deliveredPrompts, hasLength(1));
      expect(state().waypoints.single.kind, WaypointKind.scripture);
      expect(state().waypoints.single.note, isNotEmpty);
    });
  });
}
