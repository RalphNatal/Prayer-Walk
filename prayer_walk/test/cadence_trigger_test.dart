import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/activity/data/step_cadence_trigger.dart';
import 'package:prayer_walk/src/features/activity/domain/cadence_trigger.dart';

/// The arithmetic behind "every so often", on its own.
///
/// The two properties worth having tests for are the ones a walker would
/// notice: the first prompt is owed at the first interval rather than at the
/// start line, and one enormous GPS jump is one prompt rather than a burst of
/// them.
void main() {
  group('DistanceCadenceTrigger', () {
    test('nothing is due before the first interval', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 400);

      expect(trigger.isDue(0), isFalse, reason: 'the walk begins first');
      expect(trigger.isDue(120), isFalse);
      expect(trigger.isDue(399.9), isFalse);
    });

    test('one prompt at each multiple of the interval', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 400);

      expect(trigger.isDue(400), isTrue);
      expect(trigger.isDue(420), isFalse, reason: 'still inside the interval');
      expect(trigger.isDue(799), isFalse);
      expect(trigger.isDue(800), isTrue);
      expect(trigger.isDue(1201), isTrue);
    });

    test('a single large jump produces exactly one prompt', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 400);

      // A tunnel, a multipath fix, a phone that woke up in another postcode:
      // three kilometres in one step, which is seven intervals crossed.
      expect(trigger.isDue(3000), isTrue);
      expect(
        trigger.isDue(3000),
        isFalse,
        reason: 'the six skipped intervals must not be queued up',
      );
      // ...and the next one is owed at the next threshold above where the walk
      // actually is, not back at 800 m.
      expect(trigger.isDue(3100), isFalse);
      expect(trigger.isDue(3200), isTrue);
    });

    test('thresholds are absolute, so spacing cannot drift', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 400);

      expect(trigger.isDue(430), isTrue);
      // Owed at 800, not at 830 — a late fix does not push the rest of the walk
      // out of step.
      expect(trigger.isDue(800), isTrue);
    });

    test('resetting puts the walk back at the start line', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 400);
      expect(trigger.isDue(400), isTrue);

      trigger.reset();

      expect(trigger.isDue(100), isFalse);
      expect(trigger.isDue(400), isTrue);
    });

    test('a zero interval never fires rather than firing forever', () {
      final trigger = DistanceCadenceTrigger(intervalMeters: 0);
      expect(trigger.isDue(5000), isFalse);
    });

    test('it is always ready — that is the point of it', () async {
      expect(
        await DistanceCadenceTrigger(intervalMeters: 400).prepare(),
        CadenceReadiness.ready,
      );
    });
  });

  group('StepCadenceTrigger', () {
    test('the first reading is a baseline, not a measurement', () async {
      // Android reports steps since the device last booted. A walk that opens
      // on 51,200 has not walked 51,200 steps.
      // Single-subscription rather than broadcast: it buffers, so a reading
      // added before `prepare` has finished asking for permission is not lost.
      final sensor = StreamController<int>();
      final trigger = StepCadenceTrigger(
        intervalSteps: 500,
        source: sensor.stream,
      );
      addTearDown(trigger.dispose);

      final ready = trigger.prepare();
      sensor.add(51200);
      expect(await ready, CadenceReadiness.ready);

      expect(trigger.steps, 0);
      expect(trigger.isDue(0), isFalse);

      sensor.add(51699);
      await Future<void>.delayed(Duration.zero);
      expect(trigger.isDue(0), isFalse, reason: '499 steps into the interval');

      sensor.add(51700);
      await Future<void>.delayed(Duration.zero);
      expect(trigger.isDue(0), isTrue);
    });

    test('a batched late delivery is one prompt, not a backlog', () async {
      // Single-subscription rather than broadcast: it buffers, so a reading
      // added before `prepare` has finished asking for permission is not lost.
      final sensor = StreamController<int>();
      final trigger = StepCadenceTrigger(
        intervalSteps: 500,
        source: sensor.stream,
      );
      addTearDown(trigger.dispose);

      final ready = trigger.prepare();
      sensor.add(1000);
      await ready;

      // The sensor went quiet and then handed over four intervals at once.
      sensor.add(3100);
      await Future<void>.delayed(Duration.zero);

      expect(trigger.isDue(0), isTrue);
      expect(trigger.isDue(0), isFalse);
    });

    test('a sensor that never answers reports itself unavailable', () async {
      // The failure mode on hardware with no step counter: no error, no data,
      // just silence — so it has to be timed rather than caught.
      final trigger = StepCadenceTrigger(
        intervalSteps: 500,
        source: const Stream<int>.empty(),
      );
      addTearDown(trigger.dispose);

      expect(await trigger.prepare(), CadenceReadiness.unavailable);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('a sensor that errors reports itself unavailable', () async {
      final trigger = StepCadenceTrigger(
        intervalSteps: 500,
        source: Stream<int>.error(StateError('no such sensor')),
      );
      addTearDown(trigger.dispose);

      expect(await trigger.prepare(), CadenceReadiness.unavailable);
    });
  });
}
