import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../scripture/data/scripture_providers.dart';
import '../../scripture/domain/bible_translation.dart';
import '../../scripture/domain/scripture_prompt.dart';
import '../../scripture/domain/scripture_repository.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ADMINSCRIPTURE';

/// Write or edit one prompt. [promptId] null means create.
///
/// The prompt being edited is found in the list the previous screen already
/// loaded rather than fetched again — there is no `promptById` on the
/// repository, and adding one to save a round trip the list has already made
/// would be a second way to read the same row.
class AdminScriptureFormScreen extends ConsumerStatefulWidget {
  const AdminScriptureFormScreen({super.key, this.promptId});

  final String? promptId;

  @override
  ConsumerState<AdminScriptureFormScreen> createState() =>
      _AdminScriptureFormScreenState();
}

class _AdminScriptureFormScreenState
    extends ConsumerState<AdminScriptureFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _body = TextEditingController();
  final _sortOrder = TextEditingController(text: '0');

  ScripturePromptKind _kind = ScripturePromptKind.scripture;
  DevotionalCategory _category = DevotionalCategory.stillness;

  /// An explicit choice, never free text: the edition decides what the app owes
  /// whoever holds the copyright, and a typo used to be able to turn a licensed
  /// quotation into an uncredited one. A new prompt starts at whatever the
  /// build is configured to deliver, so curating for an NLT app does not mean
  /// remembering to change a field forty times.
  late BibleTranslation _translation;

  bool _published = false;
  bool _seeded = false;
  bool _saving = false;

  bool get _isEdit => widget.promptId != null;

  @override
  void initState() {
    super.initState();
    _translation = ref.read(appTranslationProvider);
  }

  @override
  void dispose() {
    _reference.dispose();
    _body.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final saved = await ref
          .read(scriptureRepositoryProvider)
          .savePrompt(
            ScripturePromptDraft(
              id: widget.promptId,
              reference: _reference.text,
              body: _body.text,
              // A prayer credits nothing, because nothing is being quoted.
              translation: _kind == ScripturePromptKind.prayer
                  ? ''
                  : _translation.id,
              kind: _kind,
              category: _category,
              isPublished: _published,
              sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
            ),
          );

      ref
        ..invalidate(allScripturePromptsProvider)
        // The walk's own copy of the library is warmed once per app run, so a
        // newly published verse would otherwise wait for a restart.
        ..invalidate(scriptureLibraryProvider);

      if (!mounted) return;
      showAppSnackBar(
        context,
        _published
            ? '"${saved.reference}" saved and live on walks.'
            : '"${saved.reference}" saved as a draft.',
      );
      context.pop();
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The prompt didn't save.",
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_isEdit) return _form(theme);

    final prompts = ref.watch(allScripturePromptsProvider);
    return AsyncView<List<ScripturePrompt>>(
      value: prompts,
      errorFallback: "That prompt couldn't be opened for editing.",
      onRetry: () => ref.invalidate(allScripturePromptsProvider),
      loading: const AdminPage(
        title: 'Edit prompt',
        showBack: true,
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              children: [
                SkeletonBox(height: 56),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 140),
              ],
            ),
          ),
        ),
      ),
      data: (items) {
        final existing = items
            .where((p) => p.id == widget.promptId)
            .firstOrNull;
        if (existing == null) {
          return AdminPage(
            title: 'Edit prompt',
            showBack: true,
            body: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'That prompt is gone',
              message: 'It may have been deleted from another session.',
              actionLabel: 'Back to prompts',
              onAction: () => context.pop(),
            ),
          );
        }
        if (!_seeded) {
          _seeded = true;
          _reference.text = existing.reference;
          _body.text = existing.body;
          _translation = existing.translationInfo;
          _sortOrder.text = existing.sortOrder.toString();
          _kind = existing.kind;
          _category = existing.category;
          _published = existing.isPublished;
        }
        return _form(theme);
      },
    );
  }

  /// What may be chosen: the editions this build carries terms for, plus the
  /// row's own if it is neither — a prompt seeded as `WEB`, or one an earlier
  /// build let somebody type by hand, must stay editable without being
  /// quietly relabelled on the first save.
  List<BibleTranslation> get _options => [
    ...BibleTranslation.values,
    if (!BibleTranslation.values.contains(_translation)) _translation,
  ];

  Widget _form(ThemeData theme) {
    final isScripture = _kind == ScripturePromptKind.scripture;

    return AdminPage(
      title: _isEdit ? 'Edit prompt' : 'New prompt',
      subtitle: _published ? 'Delivered on walks' : 'Saving as a draft',
      showBack: true,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Kind', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ScripturePromptKind>(
              segments: const [
                ButtonSegment(
                  value: ScripturePromptKind.scripture,
                  label: Text('Scripture'),
                ),
                ButtonSegment(
                  value: ScripturePromptKind.prayer,
                  label: Text('Prayer'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
            const SizedBox(height: AppSpacing.xl),

            TextFormField(
              controller: _reference,
              decoration: InputDecoration(
                labelText: isScripture ? 'Reference' : 'Name',
                hintText: isScripture ? 'Psalm 121:1-2' : 'Before the first mile',
                helperText: isScripture
                    ? 'Spoken first, so the verse can be placed before it is '
                          'understood.'
                    : "The prayer's name.",
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? (isScripture
                        ? 'Give the passage its reference.'
                        : 'Give the prayer a name.')
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _body,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Text',
                helperText:
                    'Short enough to take in at a glance, or say in one '
                    'breath.',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().length < 8)
                  ? 'Write the text that will be delivered.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Prominent, and above the fold — this is the field that carries a
            // licensing obligation, and the one an editor is most likely to
            // fill in without thinking.
            if (isScripture) ...[
              DropdownButtonFormField<BibleTranslation>(
                initialValue: _translation,
                decoration: const InputDecoration(labelText: 'Translation'),
                // The full name of an edition is long, and the console is used
                // on a phone at 2.0x text as readily as on a desktop. Let the
                // field own the width and ellipsize inside it.
                isExpanded: true,
                items: [
                  for (final translation in _options)
                    DropdownMenuItem(
                      value: translation,
                      child: Text(
                        translation.isKnown
                            ? '${translation.shortCode} · '
                                  '${translation.displayName}'
                            // An edition seeded before this list existed. Kept
                            // selectable so editing its row does not silently
                            // relabel it.
                            : '${translation.shortCode} · terms unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _translation = value);
                },
                validator: (value) =>
                    value == null ? 'Choose the edition this text came from.' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              _LicensingWarning(translation: _translation),
              const SizedBox(height: AppSpacing.xl),
            ],

            Text('Theme', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
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

            TextFormField(
              controller: _sortOrder,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sort order',
                helperText:
                    'Lower comes first. Leave gaps (10, 20, 30) so something '
                    'can be slotted between later.',
              ),
              validator: (value) =>
                  int.tryParse((value ?? '').trim()) == null
                  ? 'Whole numbers only.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('Published', style: theme.textTheme.titleSmall),
              subtitle: Text(
                _published
                    ? 'Delivered on walks from the next sync.'
                    : 'Only visible here in the console.',
                style: theme.textTheme.bodySmall,
              ),
              value: _published,
              onChanged: (value) => setState(() => _published = value),
            ),
            const SizedBox(height: AppSpacing.lg),

            PrimaryButton(
              label: _published ? 'Save and publish' : 'Save draft',
              expand: true,
              large: true,
              busy: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: AppTextButton(
                label: 'Cancel',
                onPressed: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the chosen edition obliges, said next to the field that chose it.
///
/// Data-driven rather than a fixed paragraph: the warning an editor needs for
/// WEBBE is not the warning they need for the NLT, and a stern note about
/// translations nobody is using is a note that stops being read.
class _LicensingWarning extends StatelessWidget {
  const _LicensingWarning({required this.translation});

  final BibleTranslation translation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final licensed = translation.requiresAttribution;
    final message = translation.isPublicDomain
        ? 'Public domain — no permission needed, and nothing is owed for '
              'quoting it.'
        : translation.isKnown
        ? 'Licensed. Paste ${translation.shortCode} text only from an '
              'authorised source — never typed from memory, and never copied '
              'from an unlicensed site. Every verse counts against the '
              '$kNltVerseCeiling-verse limit, no complete book may be quoted, '
              'and each quotation carries ${translation.quotationMark} '
              'automatically wherever it appears.'
        : 'This build carries no licence terms for '
              '${translation.shortCode}. Its text can\'t be published here '
              'until its terms and credit line are added to the app — ask '
              'your developer.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.balance_outlined,
          size: 16,
          color: licensed
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
