import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/utils/error_messages.dart';
import 'package:prayer_walk/src/features/profile/data/profile_row_mapper.dart';
import 'package:prayer_walk/src/features/profile/domain/profile_fields.dart';
import 'package:prayer_walk/src/features/profile/domain/profile_repository.dart';
import 'package:prayer_walk/src/features/profile/domain/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/stub_repositories.dart';

/// Editing a profile: the whole field set, the photo, and the two failures that
/// have to leave a member no worse off than before they tried.

const _viewerId = 'b6f3e1a2-0000-4000-8000-00000000000a';

/// The URL shape a real upload produces — the bucket path is what
/// [ownAvatarUrl] and [avatarObjectKey] both key off.
const _storedAvatar =
    'https://xyz.supabase.co/storage/v1/object/public/avatars/'
    '$_viewerId/8f14e45f-ea0b-4a3d-9c1f-2b7d6e5a1c33.jpg';

UserProfile _profile({String? avatarUrl}) => UserProfile(
  id: _viewerId,
  displayName: 'Maria Reyes',
  handle: '@mariareyes',
  role: UserRole.member,
  status: MemberStatus.active,
  joinedAt: DateTime(2026, 1, 4),
  accentIndex: 1,
  avatarUrl: avatarUrl,
  parish: 'Our Lady of Peace, Antipolo',
  bio: 'Walking the same four streets, most mornings.',
);

ProfileEdit _fullEdit() => const ProfileEdit(
  displayName: '  Maria Reyes-Santos  ',
  handle: 'Maria.Reyes',
  bio: 'Nurse. Night shift, morning hills.',
  parish: 'San Roque, Antipolo',
  pronouns: 'she/her',
  location: 'Antipolo, Rizal',
  links: 'prayerwalk.org/maria',
);

AvatarUpload _upload() =>
    AvatarUpload(bytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF]), edge: 512);

void main() {
  group('ProfileEdit round-trips the whole field set', () {
    test('every field comes back on the profile, trimmed', () async {
      final repo = StubProfileRepository(_profile());

      final saved = await repo.updateProfile(_viewerId, _fullEdit());

      expect(saved.displayName, 'Maria Reyes-Santos');
      expect(saved.bio, 'Nurse. Night shift, morning hills.');
      expect(saved.parish, 'San Roque, Antipolo');
      expect(saved.pronouns, 'she/her');
      expect(saved.location, 'Antipolo, Rizal');
    });

    test('the handle is stored @-prefixed and lowercased', () async {
      final repo = StubProfileRepository(_profile());

      final saved = await repo.updateProfile(_viewerId, _fullEdit());

      // `@Maria.Reyes` and `@maria.reyes` must not be able to coexist and be
      // mistaken for each other — the unique index is case-sensitive and would
      // happily keep both.
      expect(saved.handle, '@maria.reyes');
    });

    test('a link is stored normalised, not as typed', () async {
      final repo = StubProfileRepository(_profile());

      final saved = await repo.updateProfile(_viewerId, _fullEdit());

      expect(saved.links, 'https://prayerwalk.org/maria');
    });

    test('the new fields survive a read back through the shared mapper', () {
      final profile = userProfileFromRow({
        'id': _viewerId,
        'full_name': 'Maria Reyes',
        'avatar_url': _storedAvatar,
        'handle': '@mariareyes',
        'bio': 'Walking.',
        'parish': 'San Roque',
        'pronouns': 'she/her',
        'location': 'Antipolo, Rizal',
        'links': 'https://prayerwalk.org/maria',
        'role': 'member',
        'status': 'active',
        'created_at': '2026-01-04T09:15:00+00:00',
      });

      expect(profile.pronouns, 'she/her');
      expect(profile.location, 'Antipolo, Rizal');
      expect(profile.links, 'https://prayerwalk.org/maria');
      expect(profile.avatarUrl, _storedAvatar);
    });

    test('a byline row without the new columns maps to empty, not a crash', () {
      // The `author` object the feed and discovery functions build carries the
      // byline fields only. The same mapper has to take both shapes.
      final profile = userProfileFromRow({
        'id': _viewerId,
        'full_name': 'Maria Reyes',
        'avatar_url': null,
        'handle': '@mariareyes',
        'bio': '',
        'parish': '',
        'role': 'member',
        'status': 'active',
        'created_at': '2026-01-04T09:15:00+00:00',
      });

      expect(profile.pronouns, '');
      expect(profile.location, '');
      expect(profile.links, '');
      expect(profile.avatarUrl, isNull);
    });
  });

  group('a taken handle', () {
    test('a 23505 becomes the friendly line, not a Postgres code', () {
      // The real path a collision takes on this screen: the repository rethrows
      // the PostgrestException, `reportFailure` hands it to `describeFailure`
      // with the edit screen's `uniqueMessage`, and that is what the person
      // reads. Testing the shipped mapper rather than a string literal.
      final info = describeFailure(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint "profiles_handle_key"',
          code: '23505',
        ),
        fallback: "Your profile didn't save.",
        uniqueMessage: "That handle's taken — try another.",
      );

      expect(info.message, "That handle's taken — try another.");
      expect(info.isMapped, isTrue);
      // The rule the whole error mapper exists for: only a genuine transport
      // failure may tell someone to check their connection.
      expect(info.isTransport, isFalse);
      expect(info.message, isNot(contains('connection')));
      expect(info.message, isNot(contains('23505')));
    });

    test('the raw constraint text stays in the details, not on the snack bar', () {
      final info = describeFailure(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        ),
        fallback: "Your profile didn't save.",
        uniqueMessage: "That handle's taken — try another.",
      );

      expect(info.code, 'postgres:23505');
      expect(info.details, contains('duplicate key'));
      expect(info.message, isNot(contains('duplicate key')));
    });

    test('a rejected save leaves the profile as it was', () async {
      final repo = StubProfileRepository(_profile())
        ..updateError = const PostgrestException(
          message: 'duplicate key',
          code: '23505',
        );

      try {
        await repo.updateProfile(_viewerId, _fullEdit());
      } catch (_) {
        // Expected.
      }

      expect(repo.profile.displayName, 'Maria Reyes');
      expect(repo.profile.handle, '@mariareyes');
    });
  });

  group('a failed photo upload', () {
    test('leaves the previous avatar in place', () async {
      final repo = StubProfileRepository(_profile(avatarUrl: _storedAvatar))
        ..uploadError = Exception('the network went away mid-upload');

      try {
        await repo.uploadAvatar(_viewerId, _upload());
      } catch (_) {
        // Expected.
      }

      // The row is only re-pointed once the object is written, so a member who
      // loses signal keeps the face they had.
      expect(repo.profile.avatarUrl, _storedAvatar);
    });

    test('leaves a member who had no photo still on their initials', () async {
      final repo = StubProfileRepository(_profile())
        ..uploadError = Exception('offline');

      try {
        await repo.uploadAvatar(_viewerId, _upload());
      } catch (_) {
        // Expected.
      }

      expect(repo.profile.avatarUrl, isNull);
      expect(repo.profile.initials, 'MR');
    });

    test('the attempt did reach the repository, so the test is not vacuous', () async {
      final repo = StubProfileRepository(_profile())
        ..uploadError = Exception('offline');

      try {
        await repo.uploadAvatar(_viewerId, _upload());
      } catch (_) {}

      expect(repo.uploads, hasLength(1));
      expect(repo.uploads.single.edge, 512);
    });
  });

  group('removing a photo', () {
    test('clears the URL and falls back to initials', () async {
      final repo = StubProfileRepository(_profile(avatarUrl: _storedAvatar));

      final after = await repo.removeAvatar(_viewerId);

      expect(after.avatarUrl, isNull);
      expect(after.initials, 'MR');
    });

    test('a replaced photo is a new URL, so the old object can be swept', () async {
      final repo = StubProfileRepository(_profile(avatarUrl: _storedAvatar));

      final after = await repo.uploadAvatar(_viewerId, _upload());

      expect(after.avatarUrl, isNot(_storedAvatar));
      expect(avatarObjectKey(after.avatarUrl), isNotNull);
    });
  });

  group('avatar URLs the app is willing to render', () {
    test('an object in our own bucket is kept', () {
      expect(ownAvatarUrl(_storedAvatar), _storedAvatar);
    });

    test("Google's avatar URL is refused, so no feed card pings a third party", () {
      // The URL the old signup trigger copied. The migration clears these, but
      // the migration is applied by a person and the app renders `avatar_url`
      // from the moment it ships — so the client refuses them on its own.
      const google = 'https://lh3.googleusercontent.com/a/ACg8ocK_abc123=s96-c';

      expect(ownAvatarUrl(google), isNull);
    });

    test('an empty or missing column is null, not an empty URL', () {
      expect(ownAvatarUrl(''), isNull);
      expect(ownAvatarUrl('   '), isNull);
      expect(ownAvatarUrl(null), isNull);
    });

    test('the object key is the member folder and the file', () {
      expect(
        avatarObjectKey(_storedAvatar),
        '$_viewerId/8f14e45f-ea0b-4a3d-9c1f-2b7d6e5a1c33.jpg',
      );
    });

    test('a foreign URL yields no key, so the sweep cannot touch it', () {
      expect(avatarObjectKey('https://lh3.googleusercontent.com/a/x'), isNull);
      expect(avatarObjectKey(null), isNull);
    });

    test('a key survives a query string being appended', () {
      expect(
        avatarObjectKey('$_storedAvatar?v=2'),
        '$_viewerId/8f14e45f-ea0b-4a3d-9c1f-2b7d6e5a1c33.jpg',
      );
    });
  });

  group('field validation', () {
    test('a name is required and capped', () {
      expect(displayNameError(''), 'Your profile needs a name.');
      expect(displayNameError('   '), 'Your profile needs a name.');
      expect(displayNameError('Maria Reyes'), isNull);
      expect(displayNameError('M' * 61), contains('longer than'));
    });

    test('a handle has to be a handle', () {
      expect(handleError(''), 'Pick a handle.');
      expect(handleError('ab'), contains('at least 3'));
      expect(handleError('a' * 25), contains('at most 24'));
      expect(handleError('maria reyes'), contains('Letters, numbers'));
      expect(handleError('maria@reyes'), contains('Letters, numbers'));
      expect(handleError('maria/reyes'), contains('Letters, numbers'));
    });

    test('the handles people actually pick are accepted', () {
      expect(handleError('mariareyes'), isNull);
      expect(handleError('@mariareyes'), isNull);
      expect(handleError('maria.reyes'), isNull);
      expect(handleError('maria-reyes'), isNull);
      expect(handleError('maria_reyes_88'), isNull);
    });

    test('canonicalHandle stores one leading @ however many were typed', () {
      expect(canonicalHandle('maria'), '@maria');
      expect(canonicalHandle('@maria'), '@maria');
      expect(canonicalHandle('@@maria'), '@maria');
      expect(canonicalHandle('  @Maria  '), '@maria');
    });

    test('a link must be http or https', () {
      expect(profileLink('https://prayerwalk.org'), 'https://prayerwalk.org');
      expect(profileLink('http://parish.example.org'), 'http://parish.example.org');
      // Typed the way people type it.
      expect(profileLink('prayerwalk.org'), 'https://prayerwalk.org');
    });

    test('a link that is not a web address is refused outright', () {
      // The whole point of validating the scheme: none of these may reach a
      // widget that could be talked into opening them.
      expect(profileLink('javascript:alert(1)'), isNull);
      expect(profileLink('data:text/html,<script>alert(1)</script>'), isNull);
      expect(profileLink('file:///etc/passwd'), isNull);
      expect(profileLink('prayerwalk://open'), isNull);
      expect(profileLink('https://'), isNull);
    });

    test('an empty link is fine — the field is optional', () {
      expect(linkError(''), isNull);
      expect(linkError('   '), isNull);
      expect(profileLink(''), isNull);
    });

    test('a bad link says what it wants without jargon', () {
      final message = linkError('javascript:alert(1)');

      expect(message, isNotNull);
      expect(message, contains('web address'));
      expect(message, isNot(contains('scheme')));
      expect(message, isNot(contains('URI')));
    });

    test('a pasted paragraph is clamped rather than failing the save', () {
      final long = 'x' * 500;

      expect(clampField(long, ProfileLimits.bio).length, ProfileLimits.bio);
      expect(clampField('  short  ', ProfileLimits.bio), 'short');
    });
  });

  group('what a member may not edit', () {
    test('copyWith carries role and status rather than defaulting them', () {
      final admin = _profile().copyWith(
        role: UserRole.admin,
        status: MemberStatus.suspended,
      );

      // Nothing on the edit path calls this, but a copyWith that quietly reset
      // an admin to a member would be a very quiet bug.
      final renamed = admin.copyWith(displayName: 'Someone Else');

      expect(renamed.role, UserRole.admin);
      expect(renamed.status, MemberStatus.suspended);
    });

    test('copyWith can clear an avatar as well as change one', () {
      final withPhoto = _profile(avatarUrl: _storedAvatar);

      expect(withPhoto.copyWith(bio: 'new bio').avatarUrl, _storedAvatar);
      expect(withPhoto.copyWith(avatarUrl: UserProfile.noAvatar).avatarUrl, isNull);
    });
  });
}
