import 'dart:async';

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
/// save. The chime and the voice are the live screen's business and are not
/// exercised here — a test has no speaker, which is exactly why they were kept
/// out of the controller.

/// A location service driven by the test.
class _FakeLocationService extends LocationService {
  final StreamController<LocationFix> controller =
      StreamController<LocationFix>.broadcast();

  @override
  Future<LocationAccess> ensureAccess() async => LocationAccess.granted;

  @override
  Stream<LocationFix> positionStream() => controller.stream;
}

/// A fixed library, with no network under it.
class _StubScriptureRepository implements ScriptureRepository {
  const _StubScriptureRepository(this.prompts);

  final List<ScripturePrompt> prompts;

  @override
  Future<List<ScripturePrompt>> publishedPrompts({
    DevotionalCategory? category,
  }) async => category == null
      ? prompts
      : prompts.where((p) => p.category == category).toList();

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
    container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(service),
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

  group('step cadence', () {
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
      container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(service),
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
