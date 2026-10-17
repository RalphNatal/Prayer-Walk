import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/features/devotionals/domain/devotional.dart';
import 'package:prayer_walk/src/features/groups/data/church_group_row_mapper.dart';
import 'package:prayer_walk/src/features/groups/domain/church_group.dart';
import 'package:prayer_walk/src/features/groups/domain/church_group_fields.dart';
import 'package:prayer_walk/src/features/scripture/domain/bible_translation.dart';
import 'package:prayer_walk/src/features/scripture/domain/scripture_prompt.dart';

/// Church groups, without a database: the card mapping, the viewer's
/// standing, and the form rules that mirror the SQL constraints.
///
/// The rules that actually bind — who may join, who may promote whom, what a
/// group may publish — are the database's, and are tested against it in
/// `supabase/tests/database/`. These cover the app's half: reading what the
/// server said correctly, and refusing early what the server would refuse.

const _bucket =
    'https://abc.supabase.co/storage/v1/object/public/church-groups/';

Map<String, dynamic> _card({
  String? role,
  String? status,
  String policy = 'open',
  Object? avatar,
}) => {
  'id': '6a1d4c66-3333-4333-8333-333333333333',
  'name': ' St Anne ',
  'slug': 'st-anne',
  'description': 'Morning walkers.',
  'avatar_url': avatar,
  'cover_url': null,
  'city': 'Antipolo',
  'is_discoverable': false,
  'join_policy': policy,
  'created_at': '2026-10-16T08:00:00+00:00',
  'member_count': 24,
  'my_role': role,
  'my_status': status,
};

void main() {
  group('a church_group_card row', () {
    test('maps every column the RPCs return', () {
      final group = churchGroupFromRow(_card(policy: 'request'));

      expect(group.name, 'St Anne');
      expect(group.slug, 'st-anne');
      expect(group.city, 'Antipolo');
      expect(group.memberCount, 24);
      expect(group.isDiscoverable, isFalse);
      expect(group.joinPolicy, GroupJoinPolicy.request);
      expect(group.placeLine, 'St Anne, Antipolo');
    });

    test('no relationship reads as nothing, and joinable', () {
      final group = churchGroupFromRow(_card());
      expect(group.myRole, isNull);
      expect(group.myStatus, isNull);
      expect(group.canJoin, isTrue);
      expect(group.isMember, isFalse);
    });

    test('an admin is an admin only while active', () {
      expect(
        churchGroupFromRow(_card(role: 'admin', status: 'active')).isAdmin,
        isTrue,
      );
      expect(
        churchGroupFromRow(_card(role: 'admin', status: 'pending')).isAdmin,
        isFalse,
      );
    });

    test('a banned member cannot join again from the client either', () {
      final group = churchGroupFromRow(_card(role: 'member', status: 'banned'));
      expect(group.isBanned, isTrue);
      expect(group.canJoin, isFalse);
    });

    test('only images in our own bucket are drawn', () {
      expect(
        churchGroupFromRow(_card(avatar: '${_bucket}g/a.jpg')).avatarUrl,
        '${_bucket}g/a.jpg',
      );
      expect(
        churchGroupFromRow(
          _card(avatar: 'https://example.com/tracker.jpg'),
        ).avatarUrl,
        isNull,
      );
    });

    test("an image URL resolves back to its object key, for the sweep", () {
      expect(groupImageObjectKey('${_bucket}g1/x%20y.jpg?v=2'), 'g1/x y.jpg');
      expect(groupImageObjectKey('https://example.com/a.jpg'), isNull);
    });

    test('an unknown wire value does not invent a role', () {
      final group = churchGroupFromRow(_card(role: 'owner', status: 'gone'));
      expect(group.myRole, isNull);
      expect(group.myStatus, isNull);
    });
  });

  group('the roster', () {
    test('maps the nested profile through the shared mapper', () {
      final member = groupMemberFromRow({
        'profile': {
          'id': '3f0c8b7a-1111-4111-8111-111111111111',
          'full_name': 'Ana Villanueva',
          'handle': '@anav',
          'church': 'St Anne',
          'role': 'member',
          'status': 'active',
          'created_at': '2026-01-04T09:15:00+00:00',
        },
        'role': 'admin',
        'status': 'active',
        'joined_at': '2026-10-16T08:00:00+00:00',
      });
      expect(member.profile.displayName, 'Ana Villanueva');
      expect(member.profile.church, 'St Anne');
      expect(member.isAdmin, isTrue);
    });
  });

  group('joining states the policy the server will check', () {
    test('open joins active; request joins pending', () {
      expect(joinStatusFor(GroupJoinPolicy.open), 'active');
      expect(joinStatusFor(GroupJoinPolicy.request), 'pending');
    });
  });

  group('initials and tint', () {
    ChurchGroup named(String name, {String id = 'a'}) =>
        ChurchGroup(id: id, name: name, slug: 's', createdAt: DateTime(2026));

    test('first and last word, skipping marks that are not letters', () {
      expect(named('St Anne & St Joachim').initials, 'SJ');
      expect(named('Quiapo').initials, 'Q');
      expect(named('  ').initials, '?');
    });

    test('the tint is stable for an id', () {
      expect(
        named('x', id: 'g-1').accentIndex,
        named('y', id: 'g-1').accentIndex,
      );
    });
  });

  group('group names', () {
    test('mirror the SQL check: 3 to 80 characters, trimmed', () {
      expect(groupNameError(''), isNotNull);
      expect(groupNameError(' ab '), isNotNull);
      expect(groupNameError('abc'), isNull);
      expect(groupNameError('x' * GroupLimits.nameMax), isNull);
      expect(groupNameError('x' * (GroupLimits.nameMax + 1)), isNotNull);
    });
  });

  group('invite codes', () {
    test('typed loosely, read strictly', () {
      expect(normaliseInviteCode(' 7f3a-91c2 0b4e '), '7F3A91C20B4E');
      expect(isCompleteInviteCode('7f3a-91c2-0b4e'), isTrue);
      expect(isCompleteInviteCode('7f3a-91c2'), isFalse);
    });

    test('shown in fours, for reading aloud', () {
      expect(formatInviteCode('7F3A91C20B4E'), '7F3A-91C2-0B4E');
    });
  });

  // ⚖️ The form's half of the licensing rule. The database refuses all of
  // these too (scripture_prompts_group_rows_public_domain); this is the form
  // saying so before a round trip, in words.
  group('what a group admin may publish', () {
    GroupScriptureDraft draft({
      BibleTranslation translation = BibleTranslation.webbe,
      ScripturePromptKind kind = ScripturePromptKind.scripture,
      bool confirmed = true,
      String reference = 'Psalm 121:1-2',
      String body = 'I will lift up my eyes to the hills.',
    }) => GroupScriptureDraft(
      groupId: 'g',
      reference: reference,
      body: body,
      translation: translation,
      kind: kind,
      category: DevotionalCategory.stillness,
      rightsConfirmed: confirmed,
    );

    test('public-domain scripture, confirmed, is accepted', () {
      expect(groupScriptureErrors(draft()), isEmpty);
    });

    test('a prayer in their own words, quoting nobody, is accepted', () {
      expect(
        groupScriptureErrors(
          draft(
            kind: ScripturePromptKind.prayer,
            translation: BibleTranslation.none,
          ),
        ),
        isEmpty,
      );
    });

    test('the NLT is refused for a group — its allowance is the app\'s', () {
      expect(
        groupScriptureErrors(draft(translation: BibleTranslation.nlt)),
        contains('translation'),
      );
    });

    test('an edition this build has never heard of is refused too', () {
      expect(
        groupScriptureErrors(
          draft(translation: BibleTranslation.unknown('ESV')),
        ),
        contains('translation'),
      );
    });

    test('scripture must say where its wording came from', () {
      expect(
        groupScriptureErrors(draft(translation: BibleTranslation.none)),
        contains('translation'),
      );
    });

    test("a prayer doesn't claim a translation", () {
      expect(
        groupScriptureErrors(draft(kind: ScripturePromptKind.prayer)),
        contains('translation'),
      );
    });

    test('nothing is sent without confirming the right to share it', () {
      expect(groupScriptureErrors(draft(confirmed: false)), contains('rights'));
    });

    test('empty and over-long text are caught by field', () {
      expect(
        groupScriptureErrors(draft(reference: ' ')),
        contains('reference'),
      );
      expect(groupScriptureErrors(draft(body: '')), contains('body'));
      expect(
        groupScriptureErrors(draft(body: 'x' * (GroupLimits.body + 1))),
        contains('body'),
      );
    });

    test('the offered list is exactly public domain and none', () {
      expect(groupScriptureTranslations, [
        BibleTranslation.webbe,
        BibleTranslation.none,
      ]);
      expect(groupScriptureTranslations.every((t) => t.isPublicDomain), isTrue);
    });
  });
}
