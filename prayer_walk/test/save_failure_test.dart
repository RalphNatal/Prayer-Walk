import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/features/activity/data/activity_providers.dart';
import 'package:prayer_walk/src/features/activity/data/location_service.dart';
import 'package:prayer_walk/src/features/activity/data/recording_controller.dart';
import 'package:prayer_walk/src/features/activity/domain/activity.dart';
import 'package:prayer_walk/src/features/activity/domain/activity_repository.dart';
import 'package:prayer_walk/src/features/activity/presentation/activity_summary_screen.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// What the walker is told when the save fails.
///
/// The bug this pins: a `PostgrestException` carrying an exact code was
/// reported as "check your connection", and nothing was logged. These assert
/// the opposite — the real cause on screen, the details a tap away, and the
/// walk still in hand.
class _FailingRepository implements ActivityRepository {
  _FailingRepository(this.failure);

  final Object failure;
  int attempts = 0;

  @override
  Future<Activity> saveDraft(String userId, ActivityDraft draft) async {
    attempts++;
    throw failure;
  }

  @override
  Future<List<Activity>> activitiesForUser(
    String userId, {
    ActivityType? type,
  }) async => const [];

  @override
  Future<Activity> activityById(String id) async => throw UnimplementedError();

  @override
  Future<LocationReading> currentLocation() async => throw UnimplementedError();

  @override
  Future<List<PrayerIntention>> suggestedIntentions() async => const [];

  @override
  Future<void> deleteActivity(String id) async {}
}

class _FinishedRecording extends RecordingController {
  @override
  RecordingState build() => RecordingState(
    status: RecordingStatus.finished,
    draft: ActivityDraft(
      type: ActivityType.walk,
      title: 'Morning walk in Antipolo',
      startedAt: DateTime(2026, 7, 27, 6, 4),
      duration: const Duration(minutes: 20, seconds: 13),
      distanceMeters: 1213,
      elevationGainMeters: 108,
      route: const [],
      waypoints: const [],
      intentions: const [],
      placeName: 'Antipolo, Rizal',
    ),
  );
}

void main() {
  setUpAll(AppTypography.useBundledFonts);
  tearDownAll(AppTypography.useNetworkFonts);

  Future<_FailingRepository> pumpAndSave(
    WidgetTester tester,
    Object failure,
  ) async {
    final repository = _FailingRepository(failure);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordingControllerProvider.overrideWith(_FinishedRecording.new),
          activityRepositoryProvider.overrideWithValue(repository),
          currentAuthUserIdProvider.overrideWith((ref) => 'u_walker'),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ActivitySummaryScreen(),
        ),
      ),
    );
    await tester.pump();

    // The button sits below the fold on a phone.
    await tester.ensureVisible(find.text('Save walk'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save walk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return repository;
  }

  testWidgets('a missing column is named, not blamed on the network', (
    tester,
  ) async {
    await pumpAndSave(
      tester,
      PostgrestException(
        message: 'column "place_name" of relation "activities" does not exist',
        code: '42703',
      ),
    );

    expect(
      find.textContaining('out of date with the server'),
      findsOneWidget,
    );
    expect(find.textContaining('place_name'), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
  });

  testWidgets('an RLS refusal reads as a permission problem', (tester) async {
    await pumpAndSave(
      tester,
      PostgrestException(
        message: 'new row violates row-level security policy for table "activities"',
        code: '42501',
      ),
    );

    expect(find.text("You don't have permission to do that."), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
  });

  testWidgets('Details opens a copyable report carrying the code', (
    tester,
  ) async {
    await pumpAndSave(
      tester,
      PostgrestException(
        message: 'column "place_name" of relation "activities" does not exist',
        code: '42703',
      ),
    );

    await tester.tap(find.text('Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('postgres:42703'), findsOneWidget);
    expect(find.text('Copy details'), findsOneWidget);
  });

  testWidgets('the walk survives, and Retry sends it again', (tester) async {
    final repository = await pumpAndSave(
      tester,
      PostgrestException(message: 'boom', code: '42501'),
    );

    // Still on the summary screen, with the recording intact — the screen
    // shows "Nothing to save" the moment the draft is gone.
    expect(find.text('Nothing to save'), findsNothing);
    expect(find.text('Save walk'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.attempts, 2, reason: 'the same walk went again');
  });

  testWidgets('a genuine transport failure may still mention the connection', (
    tester,
  ) async {
    await pumpAndSave(tester, TimeoutException('the request never came back'));

    expect(find.textContaining('Check your connection'), findsOneWidget);
  });
}
