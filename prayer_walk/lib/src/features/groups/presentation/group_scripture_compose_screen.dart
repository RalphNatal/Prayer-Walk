import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../scripture/domain/bible_translation.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group_fields.dart';

const _tag = 'PW-GROUPS';

/// A group admin writing a verse or prayer for their members' walks.
///
/// ⚖️ Two things are asked for explicitly here rather than defaulted:
///
///  * **the translation.** Public domain (WEBBE) or none at all, for a prayer
///    in the admin's own words. It is a choice the admin makes on screen, never
///    a column default applied behind them — a row that says WEBBE should say
///    it because somebody chose it. The database refuses anything else for a
///    group's row, so NLT, ESV or NIV text cannot enter this way, and the
///    500-verse Tyndale allowance this app depends on is never spent by a
///    group.
///  * **the right to share it.** A plain confirmation, recorded with the
///    admin's name and the server's time on the row. It covers what the
///    constraint cannot see: whose words a prayer is, and whether the wording
///    of a "public domain" passage really came from the public-domain edition.
///
/// This is the same position `20260728110000_scripture_submissions.sql` takes
/// for member submissions, applied to the one other path by which somebody
/// other than CALLED Presentations puts text into a walk.
class GroupScriptureComposeScreen extends ConsumerStatefulWidget {
  const GroupScriptureComposeScreen({
    super.key,
    required this.groupId,
    this.promptId,
  });

  final String groupId;

  /// Null for a new item.
  final String? promptId;

  @override
  ConsumerState<GroupScriptureComposeScreen> createState() =>
      _GroupScriptureComposeScreenState();
}

class _GroupScriptureComposeScreenState
    extends ConsumerState<GroupScriptureComposeScreen> {
  final _reference = TextEditingController();
  final _body = TextEditingController();

  ScripturePromptKind _kind = ScripturePromptKind.scripture;
  BibleTranslation? _translation;
  DevotionalCategory _category = DevotionalCategory.stillness;
  bool _published = true;
  bool _rightsConfirmed = false;
  bool _saving = false;
  bool _filled = false;
  Map<String, String> _errors = const {};

  bool get _isEdit => widget.promptId != null;

  @override
  void dispose() {
    _reference.dispose();
    _body.dispose();
    super.dispose();
  }

  /// The row being edited, copied into the fields once. Re-confirming the
  /// right to share is deliberately *not* carried over: whoever saves new text
  /// vouches for it themselves, and the database requires as much.
  void _fill(ScripturePrompt existing) {
    if (_filled) return;
    _filled = true;
    _reference.text = existing.reference;
    _body.text = existing.body;
    _kind = existing.kind;
    _category = existing.category;
    _published = existing.isPublished;
    _translation = groupScriptureTranslations.contains(existing.translationInfo)
        ? existing.translationInfo
        : null;
  }

  GroupScriptureDraft get _draft => GroupScriptureDraft(
    id: widget.promptId,
    groupId: widget.groupId,
    reference: _reference.text,
    body: _body.text,
    // Not chosen yet is caught in [_save] and asked for by name; "none" here
    // only keeps the draft constructible until then.
    translation: _translation ?? BibleTranslation.none,
    kind: _kind,
    category: _category,
    isPublished: _published,
    rightsConfirmed: _rightsConfirmed,
  );

  void _setKind(ScripturePromptKind kind) {
    setState(() {
      _kind = kind;
      // A choice that no longer fits the kind is cleared rather than swapped
      // for the "obvious" one: the admin says where the words come from, every
      // time, and the form never says it for them.
      final fits = kind == ScripturePromptKind.prayer
          ? !(_translation?.isQuotation ?? false)
          : (_translation?.isQuotation ?? false);
      if (!fits) _translation = null;
      _errors = const {};
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    final errors = {
      ...groupScriptureErrors(draft),
      if (_translation == null)
        'translation': 'Choose where the wording comes from.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(churchGroupActionsProvider).savePrompt(draft);
      if (!mounted) return;
      showAppSnackBar(
        context,
        _published
            ? "Shared. It reaches members' walks from their next sync."
            : 'Saved as a draft.',
      );
      context.pop();
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That wasn't saved. Your words are still here.",
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEdit) return _scaffold();
    final prompts = ref.watch(groupPromptsProvider(widget.groupId));
    return AsyncView<List<ScripturePrompt>>(
      value: prompts,
      errorFallback: "That item couldn't be loaded.",
      onRetry: () => ref.invalidate(groupPromptsProvider(widget.groupId)),
      loading: Scaffold(
        appBar: AppBar(title: const Text('Edit')),
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 3, leadingSize: 0),
        ),
      ),
      isEmpty: (items) => !items.any((p) => p.id == widget.promptId),
      empty: () => Scaffold(
        appBar: AppBar(title: const Text('Edit')),
        body: EmptyState(
          icon: Icons.menu_book_outlined,
          title: "That's gone",
          message: 'It may have been deleted by another admin.',
          actionLabel: 'Go back',
          onAction: () => context.pop(),
        ),
      ),
      data: (items) {
        _fill(items.firstWhere((p) => p.id == widget.promptId));
        return _scaffold();
      },
    );
  }

  Widget _scaffold() {
    final theme = Theme.of(context);
    final isScripture = _kind == ScripturePromptKind.scripture;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit' : 'Share scripture')),
      body: ListView(
        padding: AppSpacing.listBody,
        children: [
          Text(
            'What you share reaches every member of this group on their '
            "walks, alongside the app's own library — read at a glance, or "
            'heard in one breath.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),

          SegmentedButton<ScripturePromptKind>(
            segments: const [
              ButtonSegment(
                value: ScripturePromptKind.scripture,
                label: Text('Scripture'),
                icon: Icon(Icons.menu_book_rounded),
              ),
              ButtonSegment(
                value: ScripturePromptKind.prayer,
                label: Text('Prayer'),
                icon: Icon(Icons.self_improvement_rounded),
              ),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _setKind(selection.first),
          ),
          const SizedBox(height: AppSpacing.xl),

          TextField(
            controller: _reference,
            maxLength: GroupLimits.reference,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: isScripture ? 'Passage' : 'Title',
              hintText: isScripture ? 'Psalm 121:1-2' : 'For our streets',
              errorText: _errors['reference'],
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            maxLength: GroupLimits.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: isScripture ? 'The passage, word for word' : 'Prayer',
              helperText: 'Short enough to take in at a glance.',
              errorText: _errors['body'],
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          SectionHeader(
            title: 'Where the wording comes from',
            subtitle: isScripture
                ? 'Group scripture uses the public-domain World English Bible.'
                : 'Your own words quote no translation.',
          ),
          RadioGroup<BibleTranslation>(
            groupValue: _translation,
            onChanged: (value) => setState(() {
              _translation = value;
              _errors = {..._errors}..remove('translation');
            }),
            child: Column(
              children: [
                for (final option in groupScriptureTranslations)
                  RadioListTile<BibleTranslation>(
                    contentPadding: EdgeInsets.zero,
                    value: option,
                    title: Text(
                      option.isQuotation
                          ? option.displayName
                          : 'No translation — my own words',
                    ),
                    subtitle: Text(
                      option.isQuotation
                          ? 'Public domain. Free to share.'
                          : 'A prayer or reflection you wrote.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (_errors['translation'] case final error?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),

          const SectionHeader(
            title: 'Theme',
            subtitle: 'Which kind of walk this belongs on.',
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final category in DevotionalCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          _RightsNotice(
            confirmed: _rightsConfirmed,
            error: _errors['rights'],
            onChanged: (value) => setState(() {
              _rightsConfirmed = value;
              _errors = {..._errors}..remove('rights');
            }),
          ),
          const SizedBox(height: AppSpacing.lg),

          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('Share now', style: theme.textTheme.titleSmall),
            subtitle: Text(
              _published
                  ? "Reaches members' walks from their next sync."
                  : 'Saved as a draft only admins of this group can see.',
              style: theme.textTheme.bodySmall,
            ),
            value: _published,
            onChanged: (value) => setState(() => _published = value),
          ),
          const SizedBox(height: AppSpacing.lg),

          PrimaryButton(
            label: _published ? 'Share with the group' : 'Save draft',
            expand: true,
            large: true,
            busy: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: AppTextButton(
              label: 'Cancel',
              onPressed: _saving ? null : () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// ⚖️ The confirmation, stated plainly beside the box it governs.
///
/// Short and in ordinary words, because a notice nobody reads protects
/// nobody. It names the two real cases — a passage from somewhere else, and
/// words that are someone else's — and asks for a yes.
class _RightsNotice extends StatelessWidget {
  const _RightsNotice({
    required this.confirmed,
    required this.onChanged,
    this.error,
  });

  final bool confirmed;
  final ValueChanged<bool> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = error != null;

    // A Material rather than a decorated Container: the checkbox row paints
    // its ink on the nearest Material, and under a coloured box the ripple
    // that confirms the tap would be drawn beneath the colour and never seen.
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.control,
        side: BorderSide(
          color: hasError
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your right to share this',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Most modern Bible translations are copyrighted, and so is '
              "someone else's prayer or reflection. Only share wording that is "
              'in the public domain, or that you wrote or have permission to '
              'share. Your name and the time are kept with what you share.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: confirmed,
              onChanged: (value) => onChanged(value ?? false),
              title: Text(
                'I have the right to share this text.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasError)
              Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
