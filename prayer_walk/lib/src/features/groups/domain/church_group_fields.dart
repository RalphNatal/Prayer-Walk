/// The rules a group's fields satisfy, in one place — `profile_fields.dart`'s
/// bargain for groups.
///
/// The form reads these so it can say what is wrong before a round trip; the
/// repository reads them so what reaches Postgres is already inside the `check`
/// constraints in `20261016010000_church_groups.sql`. If a number moves here it
/// moves there too.
library;

import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../scripture/domain/bible_translation.dart';
import '../../scripture/domain/scripture_prompt.dart';
import 'church_group.dart';

abstract final class GroupLimits {
  static const nameMin = 3;
  static const nameMax = 80;
  static const city = 80;
  static const description = 600;

  /// Glance-length, like the global library: a verse read mid-stride.
  static const reference = 80;
  static const body = 600;
}

/// What the create and edit forms send.
class ChurchGroupDraft {
  const ChurchGroupDraft({
    required this.name,
    this.city = '',
    this.description = '',
    this.isDiscoverable = true,
    this.joinPolicy = GroupJoinPolicy.open,
  });

  factory ChurchGroupDraft.from(ChurchGroup group) => ChurchGroupDraft(
    name: group.name,
    city: group.city,
    description: group.description,
    isDiscoverable: group.isDiscoverable,
    joinPolicy: group.joinPolicy,
  );

  final String name;
  final String city;
  final String description;
  final bool isDiscoverable;
  final GroupJoinPolicy joinPolicy;
}

/// What is wrong with [value] as a group name, or null.
String? groupNameError(String value) {
  final name = value.trim();
  if (name.isEmpty) return 'Your group needs a name.';
  if (name.length < GroupLimits.nameMin) {
    return 'Use at least ${GroupLimits.nameMin} characters — the name people '
        'would search for.';
  }
  if (name.length > GroupLimits.nameMax) {
    return 'Keep it under ${GroupLimits.nameMax} characters.';
  }
  return null;
}

/// An invite code as the server stores it: twelve hex characters, upper case.
/// People will type it with spaces, dashes and in lower case after hearing it
/// read out, and none of that should matter.
String normaliseInviteCode(String value) =>
    value.toUpperCase().replaceAll(RegExp('[^0-9A-F]'), '');

/// `7F3A91C20B4E` → `7F3A-91C2-0B4E`, which is how it is shown and read aloud.
String formatInviteCode(String code) {
  final bare = normaliseInviteCode(code);
  final groups = <String>[
    for (var i = 0; i < bare.length; i += 4)
      bare.substring(i, i + 4 > bare.length ? bare.length : i + 4),
  ];
  return groups.join('-');
}

bool isCompleteInviteCode(String value) =>
    normaliseInviteCode(value).length == 12;

// ------------------------------------------------------------- scripture ---

/// What a group admin may publish under: the public-domain edition, or
/// nothing at all for a prayer in their own words.
///
/// ⚖️ Deliberately not `BibleTranslation.values`. A group admin choosing the
/// NLT would spend CALLED Presentations' 500-verse Tyndale allowance without
/// anybody counting, and choosing the ESV or NIV has no allowance behind it at
/// all. The database refuses anything else for a group's row
/// (`scripture_prompts_group_rows_public_domain`); this list is the form
/// agreeing with it in advance rather than the protection itself.
const groupScriptureTranslations = <BibleTranslation>[
  BibleTranslation.webbe,
  BibleTranslation.none,
];

/// A group admin's verse or prayer, on its way to the table.
class GroupScriptureDraft {
  const GroupScriptureDraft({
    required this.groupId,
    required this.reference,
    required this.body,
    required this.translation,
    required this.rightsConfirmed,
    this.id,
    this.kind = ScripturePromptKind.scripture,
    this.category = DevotionalCategory.stillness,
    this.isPublished = true,
  });

  /// Null for a new prompt.
  final String? id;
  final String groupId;
  final String reference;
  final String body;

  /// Chosen explicitly on the form — never defaulted behind the admin's back —
  /// and always one of [groupScriptureTranslations].
  final BibleTranslation translation;
  final ScripturePromptKind kind;
  final DevotionalCategory category;
  final bool isPublished;

  /// The admin ticked "I have the right to share this". Without it nothing is
  /// sent: the database would refuse the row anyway, and the form should say
  /// so first.
  final bool rightsConfirmed;
}

/// Everything wrong with [draft], keyed by field, or empty.
Map<String, String> groupScriptureErrors(GroupScriptureDraft draft) {
  final errors = <String, String>{};
  final reference = draft.reference.trim();
  final body = draft.body.trim();

  if (reference.isEmpty) {
    errors['reference'] = draft.kind == ScripturePromptKind.prayer
        ? 'Give the prayer a short title.'
        : 'Name the passage — "Psalm 121:1-2" is enough.';
  } else if (reference.length > GroupLimits.reference) {
    errors['reference'] = 'Keep it under ${GroupLimits.reference} characters.';
  }

  if (body.isEmpty) {
    errors['body'] = 'Add the words a walker will read.';
  } else if (body.length > GroupLimits.body) {
    errors['body'] =
        'Keep it under ${GroupLimits.body} characters — this is read mid-walk.';
  }

  if (!groupScriptureTranslations.contains(draft.translation)) {
    errors['translation'] = 'Group scripture is public domain or a prayer.';
  } else if (draft.kind == ScripturePromptKind.scripture &&
      !draft.translation.isQuotation) {
    errors['translation'] = 'Choose the translation this passage is from.';
  } else if (draft.kind == ScripturePromptKind.prayer &&
      draft.translation.isQuotation) {
    errors['translation'] =
        "A prayer in your own words doesn't quote a "
        'translation.';
  }

  if (!draft.rightsConfirmed) {
    errors['rights'] = 'Confirm you have the right to share this.';
  }
  return errors;
}
