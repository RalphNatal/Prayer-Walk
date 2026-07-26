import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/data/recording_controller.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';

/// A location service driven by the test rather than the device.
class _FakeLocationService extends LocationService {
  _FakeLocationService({this.access = LocationAccess.granted});

  final LocationAccess access;
  final StreamController<LocationFix> controller =
      StreamController<LocationFix>.broadcast();

  int streamsOpened = 0;
  int streamsClosed = 0;

  @override
  Future<LocationAccess> ensureAccess() async => access;

  @override
  Stream<LocationFix> positionStream() {
    streamsOpened++;
    // Counts cancellations so a leaked subscription is visible to the test.
    return controller.stream.transform(
      StreamTransformer<LocationFix, LocationFix>.fromHandlers(
        handleDone: (sink) => sink.close(),
      ),
    ).doOnCancel(() => streamsClosed++);
  }
}

/// `doOnCancel` isn't in dart:async — the two lines it takes are cheaper than
/// pulling in rxdart for one test helper.
extension _OnCancel<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() onCancel) {
    late StreamController<T> out;
    StreamSubscription<T>? sub;
    out = StreamController<T>(
      onListen: () => sub = listen(out.add, onError: out.addError),
      onCancel: () {
        onCancel();
        return sub?.cancel();
      },
    );
    return out.stream;
  }
}

/// A fix at [lat]/[lng]. Accuracy defaults to something the filter accepts.
LocationFix fixAt(
  double lat,
  double lng, {
  double accuracy = 5,
  double altitude = 10,
}) => LocationFix(
  point: LatLng(lat, lng),
  accuracyMeters: accuracy,
  altitudeMeters: altitude,
  timestamp: DateTime.now(),
);

void main() {
  late _FakeLocationService service;
  late ProviderContainer container;

  RecordingController controller() =>
      container.read(recordingControllerProvider.notifier);
  RecordingState state() => container.read(recordingControllerProvider);

  void setUpWith(LocationAccess access) {
    service = _FakeLocationService(access: access);
    container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
  }

  setUp(() => setUpWith(LocationAccess.granted));

  /// Emits a fix and lets the controller's listener run.
  Future<void> emit(LocationFix fix) async {
    service.controller.add(fix);
    await Future<void>.delayed(Duration.zero);
  }

  group('permission gate', () {
    test('a denial does not start recording and is reported back', () async {
      setUpWith(LocationAccess.deniedForever);

      final access = await controller().start();

      expect(access, LocationAccess.deniedForever);
      expect(state().status, RecordingStatus.idle);
      expect(state().access, LocationAccess.deniedForever);
      expect(service.streamsOpened, 0, reason: 'no stream on a denial');
    });

    test('a grant opens exactly one stream', () async {
      await controller().start();

      expect(state().status, RecordingStatus.recording);
      expect(service.streamsOpened, 1);
    });
  });

  group('distance accumulation', () {
    test('the first fix starts the route without adding distance', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));

      expect(state().route, hasLength(1));
      expect(state().distanceMeters, 0);
    });

    test('moving accumulates roughly the real ground distance', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      // ~111 m north.
      await emit(fixAt(14.5804, 121.0359));

      expect(state().route, hasLength(2));
      expect(state().distanceMeters, closeTo(111, 3));
    });

    test('standing still does not inflate distance', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));

      // Twenty fixes of sub-metre jitter — the shape of standing at a corner.
      for (var i = 0; i < 20; i++) {
        await emit(fixAt(14.5794 + (i.isEven ? 0.000004 : -0.000004), 121.0359));
      }

      expect(state().distanceMeters, 0);
    });

    test('a fix with a wide accuracy radius is discarded', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      await emit(fixAt(14.5804, 121.0359, accuracy: 80));

      expect(state().route, hasLength(1), reason: 'the bad fix is not plotted');
      expect(state().distanceMeters, 0);
    });

    test('only positive altitude deltas count as climb', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359, altitude: 20));
      await emit(fixAt(14.5804, 121.0359, altitude: 30)); // +10
      await emit(fixAt(14.5814, 121.0359, altitude: 12)); // descent, ignored

      expect(state().elevationGainMeters, closeTo(10, 0.01));
    });
  });

  group('pause and resume', () {
    test('positions are ignored while paused', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      await emit(fixAt(14.5804, 121.0359));
      final walked = state().distanceMeters;

      controller().pause();
      await emit(fixAt(14.5904, 121.0359)); // a long way off
      await emit(fixAt(14.6004, 121.0359));

      expect(state().distanceMeters, walked);
      expect(state().route, hasLength(2));
    });

    test('resuming does not measure the jump across the paused gap', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      await emit(fixAt(14.5804, 121.0359));
      final walked = state().distanceMeters;

      controller().pause();
      controller().resume();

      // Resumed a kilometre away — a car ride, a paused coffee stop. The first
      // post-resume fix must start a fresh segment, not draw a line back.
      await emit(fixAt(14.5904, 121.0359));
      expect(
        state().distanceMeters,
        walked,
        reason: 'the first fix after a resume contributes nothing',
      );

      // ...and normal accumulation continues from there.
      await emit(fixAt(14.5914, 121.0359));
      expect(state().distanceMeters, closeTo(walked + 111, 3));
    });

    test('togglePause round-trips the status', () async {
      await controller().start();
      expect(state().status, RecordingStatus.recording);
      controller().togglePause();
      expect(state().status, RecordingStatus.paused);
      expect(state().isPaused, isTrue);
      controller().togglePause();
      expect(state().status, RecordingStatus.recording);
    });

    test('paused seconds do not count toward elapsed time', () async {
      await controller().start();
      controller().pause();

      // Two real ticks' worth of wall clock, all of it paused.
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(state().elapsed, Duration.zero);
    });

    test('elapsed advances while recording', () async {
      await controller().start();
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(state().elapsed.inSeconds, greaterThanOrEqualTo(2));
    });
  });

  group('waypoints', () {
    test('a waypoint pins the current point and the elapsed time', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));

      controller().dropWaypoint(WaypointKind.gratitude);

      expect(state().waypoints, hasLength(1));
      expect(state().waypoints.single.point, const LatLng(14.5794, 121.0359));
      expect(state().waypoints.single.label, 'Gave thanks');
    });

    test('a waypoint before the first fix is refused, not crashed', () async {
      await controller().start();
      controller().dropWaypoint(WaypointKind.stillness);
      expect(state().waypoints, isEmpty);
    });
  });

  group('lifecycle', () {
    test('finish assembles a draft from what was recorded', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      await emit(fixAt(14.5804, 121.0359));
      controller().finish();

      final draft = state().draft;
      expect(draft, isNotNull);
      expect(state().status, RecordingStatus.finished);
      expect(draft!.route, hasLength(2));
      expect(draft.distanceMeters, closeTo(111, 3));
      expect(draft.title, isNotEmpty);
    });

    test('finish releases the position stream', () async {
      await controller().start();
      controller().finish();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 1, reason: 'no leaked GPS subscription');
    });

    test('reset releases the position stream mid-walk', () async {
      await controller().start();
      await emit(fixAt(14.5794, 121.0359));
      controller().reset();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 1);
      expect(state().status, RecordingStatus.idle);
      expect(state().route, isEmpty);
    });

    test('disposing the container releases the position stream', () async {
      await controller().start();
      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(service.streamsClosed, 1);
    });
  });
}
