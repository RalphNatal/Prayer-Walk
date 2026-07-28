import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../../scripture/data/scripture_providers.dart';
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
  final _translation = TextEditingController(text: 'WEBBE');
  final _sortOrder = TextEditingController(text: '0');

  ScripturePromptKind _kind = ScripturePromptKind.scripture;
  DevotionalCategory _category = DevotionalCategory.stillness;
  bool _published = false;
  bool _seeded = false;
  bool _saving = false;

  bool get _isEdit => widget.promptId != null;

  @override
  void dispose() {
    _reference.dispose();
    _body.dispose();
    _translation.dispose();
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
                  : _translation.text,
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
          _translation.text = existing.translation;
          _sortOrder.text = existing.sortOrder.toString();
          _kind = existing.kind;
          _category = existing.category;
          _published = existing.isPublished;
        }
        return _form(theme);
      },
    );
  }

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
              TextFormField(
                controller: _translation,
                decoration: const InputDecoration(
                  labelText: 'Translation',
                  hintText: 'WEBBE',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Name the edition this text came from.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              const _LicensingWarning(),
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

class _LicensingWarning extends StatelessWidget {
  const _LicensingWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.balance_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Public domain only. WEBBE is the default and needs no permission. '
            'NIV, ESV, NLT, NASB and CSB are licensed — do not paste their '
            'text here.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
