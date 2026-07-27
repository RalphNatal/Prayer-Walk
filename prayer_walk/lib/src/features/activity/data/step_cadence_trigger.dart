import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/app_logger.dart';
import '../domain/cadence_trigger.dart';

/// The only file in the app that imports `pedometer` or `permission_handler`.
///
/// Same bargain `location_service.dart` makes with geolocator and
/// `route_map_view.dart` makes with flutter_map: the plugin is sealed in one
/// file, and everything above it speaks [CadenceTrigger].
///
/// Three things make step counting harder than it sounds, and all three are
/// handled here:
///
///  * **The reading is not a walk's step count.** Android's `TYPE_STEP_COUNTER`
///    reports steps since the device last booted, so the first sample of a walk
///    is a baseline to subtract, not a measurement.
///  * **The sensor is genuinely optional hardware.** Several handsets — some
///    Samsung models notably — have no step counter at all, and the stream
///    simply never produces anything. That is reported as
///    [CadenceReadiness.unavailable] so the caller can fall back to distance,
///    not swallowed into a walk that quietly never delivers a verse.
///  * **The permission is not free.** On Android 10+ `ACTIVITY_RECOGNITION` is
///    a runtime permission, and it is requested *here* — reached only when
///    somebody has actually chosen step cadence. It is never asked at first
///    launch, and a walker who never opens the cadence sheet is never asked at
///    all. iOS prompts by itself the first time CoreMotion is queried, using
///    `NSMotionUsageDescription`; there is nothing to request from Dart.
class StepCadenceTrigger implements CadenceTrigger {
  StepCadenceTrigger({required this.intervalSteps, this.source})
    : _next = intervalSteps;

  final int intervalSteps;

  /// Injectable so the trigger's arithmetic can be tested without a sensor.
  /// Null uses the real pedometer.
  final Stream<int>? source;

  static const _tag = 'PW-CADENCE';

  /// How long to wait for the sensor's first sample before calling it absent.
  ///
  /// A step counter that exists answers on subscription, near-instantly. One
  /// that does not exist never answers at all, and there is no error to catch —
  /// silence *is* the failure mode, so it has to be timed.
  static const _probe = Duration(seconds: 3);

  StreamSubscription<int>? _subscription;

  /// The reading at the moment the walk began. Everything is measured from it.
  int? _baseline;
  int _steps = 0;
  int _next;

  @override
  Future<CadenceReadiness> prepare() async {
    if (!await _ensurePermission()) return CadenceReadiness.unavailable;

    final first = Completer<void>();
    try {
      _subscription = _stream().listen(
        (steps) {
          _baseline ??= steps;
          _steps = steps - _baseline!;
          if (!first.isCompleted) first.complete();
        },
        onError: (Object error) {
          if (!first.isCompleted) first.completeError(error);
        },
        onDone: () {
          // A stream that closes before it ever reported is a sensor that is
          // not there. Answering now saves waiting out the whole probe.
          if (!first.isCompleted) {
            first.completeError(StateError('step stream closed with no data'));
          }
        },
        cancelOnError: false,
      );
    } catch (error) {
      AppLogger.info(_tag, 'step sensor refused a listener (${error.runtimeType})');
      return _giveUp();
    }

    try {
      await first.future.timeout(_probe);
    } on TimeoutException {
      // No hardware, or a sensor that will not report. Either way this walk is
      // measured in metres.
      AppLogger.info(_tag, 'no step sensor reading in ${_probe.inSeconds}s');
      return _giveUp();
    } catch (error) {
      AppLogger.info(_tag, 'step sensor failed (${error.runtimeType})');
      return _giveUp();
    }

    return CadenceReadiness.ready;
  }

  /// Steps taken since [prepare] captured the baseline. Zero before then.
  int get steps => _steps;

  @override
  bool isDue(double distanceMeters) {
    // Distance is not consulted: this trigger is paced by the sensor, and the
    // caller passes the walk's distance to every trigger without knowing which
    // one it is holding.
    if (intervalSteps <= 0) return false;
    if (_steps < _next) return false;
    // Same rule as the distance trigger: one per call, and no backlog if the
    // sensor batched several minutes of steps into a single late delivery.
    _next = ((_steps ~/ intervalSteps) + 1) * intervalSteps;
    return true;
  }

  @override
  void reset() {
    _baseline = null;
    _steps = 0;
    _next = intervalSteps;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Stream<int> _stream() =>
      source ?? Pedometer.stepCountStream.map((count) => count.steps);

  Future<CadenceReadiness> _giveUp() async {
    dispose();
    return CadenceReadiness.unavailable;
  }

  /// Android only. Reaching this method is the moment the walker opted in, so
  /// the prompt is expected here and nowhere earlier.
  Future<bool> _ensurePermission() async {
    // An injected source is not the device's pedometer, so there is nothing to
    // ask anybody about.
    if (source != null) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final status = await Permission.activityRecognition.request();
      if (status.isGranted) return true;
      AppLogger.info(_tag, 'activity recognition not granted ($status)');
      return false;
    } catch (error) {
      // No plugin (a test, a desktop build) is not a refusal worth reporting —
      // the sensor probe below will settle it either way.
      AppLogger.info(_tag, 'permission check unavailable (${error.runtimeType})');
      return false;
    }
  }
}

/// Builds the step trigger for a walk.
///
/// A provider rather than a direct constructor call so the recorder can be
/// tested against a scripted sensor — and so nothing outside this file has to
/// name the pedometer.
typedef StepTriggerBuilder = CadenceTrigger Function(int intervalSteps);

final stepTriggerBuilderProvider = Provider<StepTriggerBuilder>(
  (ref) => (intervalSteps) => StepCadenceTrigger(intervalSteps: intervalSteps),
);
