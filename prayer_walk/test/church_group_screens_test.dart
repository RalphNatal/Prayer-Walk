import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/features/auth/data/auth_providers.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/discovery/data/discovery_providers.dart';
import 'package:prayer_walk/src/features/discovery/domain/discovery_repository.dart';
import 'package:prayer_walk/src/features/discovery/domain/member_card.dart';
import 'package:prayer_walk/src/features/discovery/presentation/discover_screen.dart';
import 'package:prayer_walk/src/features/groups/data/church_group_providers.dart';
import 'package:prayer_walk/src/features/groups/domain/church_group.dart';
import 'package:prayer_walk/src/features/groups/presentation/church_group_screen.dart';
import 'package:prayer_walk/src/features/groups/presentation/group_members_screen.dart';
import 'package:prayer_walk/src/features/groups/presentation/group_scripture_compose_screen.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';

import 'support/stub_repositories.dart';

/// The group screens doing what they say: joining, asking, approving,
/// composing — and saying the right thing in each state, in both themes, with
/// targets a thumb can hit.

const _me = 'b6f3e1a2-0000-4000-8000-00000000000a';

ChurchGroup church({
  String id = 'g-anne',
  String name = 'St Anne',
  GroupRole? role,
  MembershipStatus? status,
  GroupJoinPolicy policy = GroupJoinPolicy.open,
  bool discoverable = true,
}) => ChurchGroup(
  id: id,
  name: name,
  slug: 'st-anne',
  createdAt: DateTime(2026, 10, 1),
  city: 'Antipolo',
  description: 'Morning walkers, most days, from the cathedral steps.',
  isDiscoverable: discoverable,
  joinPolicy: policy,
  memberCount: 24,
  myRole: role,
  myStatus: status,
);

GroupMember member(
  String id,
  String name, {
  GroupRole role = GroupRole.member,
  MembershipStatus status = MembershipStatus.active,
}) => GroupMember(
  profile: UserProfile(
    id: id,
    displayName: name,
    handle: '@${name.toLowerCase().replaceAll(' ', '')}',
    role: UserRole.member,
    status: MemberStatus.active,
    joinedAt: DateTime(2026),
    accentIndex: 2,
  ),
  role: role,
  status: status,
  joinedAt: DateTime(2026, 9, 1),
);

final _roster = [
  member(_me, 'Maria Reyes', role: GroupRole.admin),
  member('u-ana', 'Ana Villanueva'),
  member('u-ben', 'Ben Cruz', status: MembershipStatus.pending),
];

const _verse = ScripturePrompt(
  id: 'p-1',
  reference: 'Isaiah 40:31',
  body: 'Those who wait for Yahweh will renew their strength.',
  translation: 'WEBBE',
  category: DevotionalCategory.stillness,
  groupId: 'g-anne',
  groupName: 'St Anne',
);

class _NoDiscovery implements DiscoveryRepository {
  const _NoDiscovery();
  @override
  Future<List<MemberCard>> searchMembers(
    String query, {
    int limit = 20,
  }) async => const [];
  @override
  Future<List<MemberCard>> suggestedMembers({int limit = 8}) async => const [];
}

/// A few frames, enough for a write to land, its invalidation to re-read, and
/// a sheet or switcher to finish its transition. Not pumpAndSettle: skeletons
/// shimmer forever by design.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<FakeChurchGroupRepository> pump(
  WidgetTester tester,
  Widget screen, {
  List<ChurchGroup>? groups,
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 900);
  addTearDown(tester.view.reset);

  final repo = FakeChurchGroupRepository(
    groups: groups ?? [church()],
    roster: _roster,
    prompts: [_verse],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        churchGroupRepositoryProvider.overrideWithValue(repo),
        discoveryRepositoryProvider.overrideWithValue(const _NoDiscovery()),
        currentAuthUserIdProvider.overrideWith((ref) => _me),
      ],
      child: MaterialApp(theme: theme ?? AppTheme.light(), home: screen),
    ),
  );
  await tester.pump();
  await settle(tester);
  return repo;
}

void main() {
  group('the group page', () {
    testWidgets('a visitor is told what joining does, then joins', (
      tester,
    ) async {
      final repo = await pump(
        tester,
        const ChurchGroupScreen(groupId: 'g-anne'),
      );

      expect(find.text('St Anne'), findsWidgets);
      expect(find.textContaining('Join to have them arrive'), findsOneWidget);
      // Members-only content stays members-only on screen, too.
      expect(find.text('Isaiah 40:31'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await settle(tester);

      expect(repo.joined, ['g-anne']);
      expect(find.text('Joined'), findsOneWidget);
      expect(find.text('Isaiah 40:31'), findsOneWidget);
    });

    testWidgets('a request-only group asks, and then says it is waiting', (
      tester,
    ) async {
      await pump(
        tester,
        const ChurchGroupScreen(groupId: 'g-anne'),
        groups: [church(policy: GroupJoinPolicy.request)],
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Ask to join'));
      await settle(tester);

      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Isaiah 40:31'), findsNothing);
    });

    testWidgets('a member reads the church scripture with its credit', (
      tester,
    ) async {
      await pump(
        tester,
        const ChurchGroupScreen(groupId: 'g-anne'),
        groups: [
          church(role: GroupRole.member, status: MembershipStatus.active),
        ],
      );
      expect(find.text('Isaiah 40:31'), findsOneWidget);
      expect(find.text('WEBBE'), findsOneWidget);
      expect(find.text('You look after this group'), findsNothing);
    });

    testWidgets('an admin sees the panel, and the waiting request', (
      tester,
    ) async {
      await pump(
        tester,
        const ChurchGroupScreen(groupId: 'g-anne'),
        groups: [
          church(role: GroupRole.admin, status: MembershipStatus.active),
        ],
      );
      expect(find.text('You look after this group'), findsOneWidget);
      expect(find.text('1 request waiting'), findsOneWidget);
    });

    testWidgets('the join button names the group to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const ChurchGroupScreen(groupId: 'g-anne'));
      expect(find.bySemanticsLabel(RegExp('Join St Anne')), findsOneWidget);
      handle.dispose();
    });

    for (final (label, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('meets tap-target and contrast guidelines — $label', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(
          tester,
          const ChurchGroupScreen(groupId: 'g-anne'),
          groups: [
            church(role: GroupRole.admin, status: MembershipStatus.active),
          ],
          theme: theme,
        );
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('a group that is gone says so, rather than spinning', (
      tester,
    ) async {
      await pump(tester, const ChurchGroupScreen(groupId: 'g-missing'));
      expect(find.textContaining("That's gone"), findsOneWidget);
    });
  });

  group('the members screen', () {
    testWidgets('an admin lets a waiting member in', (tester) async {
      final repo = await pump(
        tester,
        const GroupMembersScreen(groupId: 'g-anne'),
        groups: [
          church(role: GroupRole.admin, status: MembershipStatus.active),
        ],
      );

      expect(find.text('Waiting to join'), findsOneWidget);
      await tester.tap(find.byTooltip('Let Ben Cruz in'));
      await settle(tester);

      expect(repo.statusChanges, [
        ('g-anne', 'u-ben', MembershipStatus.active),
      ]);
    });

    testWidgets('nobody is offered controls on their own row', (tester) async {
      await pump(
        tester,
        const GroupMembersScreen(groupId: 'g-anne'),
        groups: [
          church(role: GroupRole.admin, status: MembershipStatus.active),
        ],
      );
      expect(find.byTooltip('Manage Maria Reyes'), findsNothing);
      expect(find.byTooltip('Manage Ana Villanueva'), findsOneWidget);
    });

    testWidgets('a plain member sees the roster and no controls', (
      tester,
    ) async {
      await pump(
        tester,
        const GroupMembersScreen(groupId: 'g-anne'),
        groups: [
          church(role: GroupRole.member, status: MembershipStatus.active),
        ],
      );
      expect(find.text('Ana Villanueva'), findsOneWidget);
      expect(find.text('Waiting to join'), findsNothing);
      expect(find.byTooltip('Manage Ana Villanueva'), findsNothing);
    });
  });

  group('sharing scripture with the group', () {
    Future<void> scrollTo(WidgetTester tester, Finder finder) =>
        tester.scrollUntilVisible(
          finder,
          150,
          scrollable: find.byType(Scrollable).first,
        );

    testWidgets('nothing is sent until the right to share is confirmed', (
      tester,
    ) async {
      final repo = await pump(
        tester,
        const GroupScriptureComposeScreen(groupId: 'g-anne'),
      );

      await tester.enterText(find.byType(TextField).at(0), 'Psalm 121:1-2');
      await tester.enterText(
        find.byType(TextField).at(1),
        'I will lift up my eyes to the hills.',
      );
      await scrollTo(tester, find.text('World English Bible, British Edition'));
      await tester.tap(find.text('World English Bible, British Edition'));
      await scrollTo(tester, find.text('Share with the group'));
      await tester.tap(find.text('Share with the group'));
      await tester.pump();

      expect(repo.savedPrompts, isEmpty);
      await scrollTo(
        tester,
        find.text('Confirm you have the right to share this.'),
      );
      expect(
        find.text('Confirm you have the right to share this.'),
        findsOneWidget,
      );

      await tester.tap(find.text('I have the right to share this text.'));
      await scrollTo(tester, find.text('Share with the group'));
      await tester.tap(find.text('Share with the group'));
      await settle(tester);

      expect(repo.savedPrompts, hasLength(1));
      expect(repo.savedPrompts.single.translation, BibleTranslation.webbe);
      expect(repo.savedPrompts.single.rightsConfirmed, isTrue);
    });

    testWidgets('the translation is never chosen for the admin', (
      tester,
    ) async {
      final repo = await pump(
        tester,
        const GroupScriptureComposeScreen(groupId: 'g-anne'),
      );
      await tester.enterText(find.byType(TextField).at(0), 'Psalm 23:1');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Yahweh is my shepherd.',
      );
      await scrollTo(tester, find.text('I have the right to share this text.'));
      await tester.tap(find.text('I have the right to share this text.'));
      await scrollTo(tester, find.text('Share with the group'));
      await tester.tap(find.text('Share with the group'));
      await tester.pump();

      expect(repo.savedPrompts, isEmpty);
      await scrollTo(tester, find.text('Choose where the wording comes from.'));
      expect(find.text('Choose where the wording comes from.'), findsOneWidget);
    });

    testWidgets('no licensed translation is even offered', (tester) async {
      await pump(tester, const GroupScriptureComposeScreen(groupId: 'g-anne'));
      expect(find.textContaining('New Living Translation'), findsNothing);
      expect(find.textContaining('NLT'), findsNothing);
    });
  });

  group('Discover', () {
    testWidgets('opens on Churches when asked, with yours first', (
      tester,
    ) async {
      await pump(
        tester,
        const DiscoverScreen(initialTab: DiscoverTab.churches),
        groups: [
          church(role: GroupRole.member, status: MembershipStatus.active),
          church(id: 'g-roque', name: 'San Roque'),
        ],
      );
      expect(find.text('Your churches'), findsOneWidget);
      expect(find.text('Churches on Prayer Walk'), findsOneWidget);
      expect(find.text('San Roque'), findsWidgets);
      expect(find.text('Member'), findsWidgets);
    });

    testWidgets('no church yet is an invitation, not a blank', (tester) async {
      await pump(
        tester,
        const DiscoverScreen(initialTab: DiscoverTab.churches),
        groups: [church(id: 'g-roque', name: 'San Roque')],
      );
      expect(
        find.textContaining("You haven't joined a church yet"),
        findsOneWidget,
      );
      expect(find.text('Start a group'), findsOneWidget);
      expect(find.text('Join with a code'), findsOneWidget);
    });

    testWidgets('a code is checked and shown before anything is joined', (
      tester,
    ) async {
      final repo = await pump(
        tester,
        const DiscoverScreen(initialTab: DiscoverTab.churches),
      );
      await tester.tap(find.text('Join with a code'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, '7f3a-91c2-0b4e');
      await tester.tap(find.text('Find group'));
      await settle(tester);

      expect(find.text('Join St Anne'), findsOneWidget);
      expect(repo.joined, isEmpty);
    });
  });
}
