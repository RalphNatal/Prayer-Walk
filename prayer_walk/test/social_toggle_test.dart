import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/social/data/social_actions.dart';
import 'package:prayer_walk/src/features/social/data/social_providers.dart';
import 'package:prayer_walk/src/features/social/presentation/optimistic_toggle.dart';

import 'support/stub_repositories.dart';

const _viewer = 'f1e2d3c4-0000-4000-8000-000000000001';
const _walk = 'f1e2d3c4-0000-4000-8000-0000000000a1';
const _other = 'f1e2d3c4-0000-4000-8000-0000000000b2';

ProviderContainer _container(FakeSocialRepository social) {
  final container = ProviderContainer(
    overrides: [
      socialRepositoryProvider.overrideWith((ref) => social),
      currentAuthUserIdProvider.overrideWith((ref) => _viewer),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SocialActions', () {
    test('encouraging twice adds the blessing and then withdraws it', () async {
      final social = FakeSocialRepository();
      final actions = _container(social).read(socialActionsProvider);

      expect(await actions.toggleEncouragement(_walk), isTrue);
      expect(social.encouragements, contains((_walk, _viewer)));

      expect(await actions.toggleEncouragement(_walk), isFalse);
      expect(social.encouragements, isEmpty);
    });

    test('encouraging never double-counts the same viewer', () async {
      final social = FakeSocialRepository();
      final actions = _container(social).read(socialActionsProvider);

      await actions.toggleEncouragement(_walk);
      await actions.toggleEncouragement(_walk);
      await actions.toggleEncouragement(_walk);

      expect(social.encouragements, hasLength(1));
    });

    test('following twice follows and then unfollows', () async {
      final social = FakeSocialRepository();
      final actions = _container(social).read(socialActionsProvider);

      expect(await actions.toggleFollow(_other), isTrue);
      expect(social.follows, contains((_viewer, _other)));

      expect(await actions.toggleFollow(_other), isFalse);
      expect(social.follows, isEmpty);
    });

    test('a comment is attributed to the signed-in person', () async {
      final social = FakeSocialRepository();
      final actions = _container(social).read(socialActionsProvider);

      await actions.addComment(_walk, 'Holding Lola Iding with you.');

      expect(social.comments.single.authorId, _viewer);
      expect(social.comments.single.body, 'Holding Lola Iding with you.');
    });

    test('signed out, nothing is written and nothing pretends it was', () async {
      final social = FakeSocialRepository();
      final container = ProviderContainer(
        overrides: [
          socialRepositoryProvider.overrideWith((ref) => social),
          currentAuthUserIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);
      final actions = container.read(socialActionsProvider);

      expect(await actions.toggleEncouragement(_walk), isNull);
      expect(await actions.toggleFollow(_other), isNull);
      await actions.addComment(_walk, 'hello');

      expect(social.encouragements, isEmpty);
      expect(social.follows, isEmpty);
      expect(social.comments, isEmpty);
    });

    test('a failed write is not swallowed — the caller has to revert', () {
      final actions = _container(FailingSocialRepository()).read(
        socialActionsProvider,
      );

      expect(actions.toggleEncouragement(_walk), throwsException);
      expect(actions.toggleFollow(_other), throwsException);
    });
  });

  group('OptimisticToggle', () {
    Widget harness({
      required bool value,
      required Future<bool?> Function() onToggle,
      void Function(Object, StackTrace)? onFailure,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: OptimisticToggle(
            value: value,
            onToggle: onToggle,
            onFailure: onFailure,
            builder: (context, on, delta, toggle) => TextButton(
              onPressed: toggle,
              child: Text('${on ? 'sent' : 'send'} ${3 + delta}'),
            ),
          ),
        ),
      );
    }

    testWidgets('answers before the write lands, and moves the count', (
      tester,
    ) async {
      final pending = Completer<bool?>();
      await tester.pumpWidget(
        harness(value: false, onToggle: () => pending.future),
      );

      expect(find.text('send 3'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      // Nothing has come back yet; the button already reads as done.
      expect(find.text('sent 4'), findsOneWidget);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('sent 4'), findsOneWidget);
    });

    testWidgets('reverts and reports when the write fails', (tester) async {
      Object? reported;
      StackTrace? reportedStack;
      await tester.pumpWidget(
        harness(
          value: false,
          onToggle: () async => throw Exception('offline'),
          onFailure: (error, stack) {
            reported = error;
            reportedStack = stack;
          },
        ),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.text('send 3'), findsOneWidget);
      expect(reported, isA<Exception>());
      // The stack travels with the error — reporting one without the other is
      // what made these failures undiagnosable.
      expect(reportedStack, isNotNull);
    });

    testWidgets('shows what the server settled on when it disagrees', (
      tester,
    ) async {
      await tester.pumpWidget(
        // The row was already there — the server says "still encouraged".
        harness(value: true, onToggle: () async => true),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.text('sent 3'), findsOneWidget);
    });

    testWidgets('a second tap while the first is in flight is ignored', (
      tester,
    ) async {
      var calls = 0;
      final pending = Completer<bool?>();
      await tester.pumpWidget(
        harness(
          value: false,
          onToggle: () {
            calls++;
            return pending.future;
          },
        ),
      );

      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(calls, 1);

      pending.complete(true);
      await tester.pumpAndSettle();
    });
  });
}
