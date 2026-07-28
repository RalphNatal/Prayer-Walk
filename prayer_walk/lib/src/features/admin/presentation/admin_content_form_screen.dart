import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/data/devotional_providers.dart';
import '../../devotionals/domain/devotional.dart';
import '../../profile/data/profile_providers.dart';
import '../data/admin_providers.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-ADMINCONTENT';

/// Create or edit a devotional. [devotionalId] null means create.
class AdminContentFormScreen extends ConsumerStatefulWidget {
  const AdminContentFormScreen({super.key, this.devotionalId});

  final String? devotionalId;

  @override
  ConsumerState<AdminContentFormScreen> createState() =>
      _AdminContentFormScreenState();
}

class _AdminContentFormScreenState
    extends ConsumerState<AdminContentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _body = TextEditingController();
  final _scriptureRef = TextEditingController();
  final _scriptureText = TextEditingController();

  DevotionalCategory _category = DevotionalCategory.morningLight;
  bool _published = false;
  bool _seeded = false;
  bool _saving = false;

  bool get _isEdit => widget.devotionalId != null;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _body.dispose();
    _scriptureRef.dispose();
    _scriptureText.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final authorName =
        ref.read(currentProfileProvider).value?.displayName ?? 'Admin';

    try {
      final saved = await ref.read(devotionalRepositoryProvider).save(
        DevotionalDraft(
          id: widget.devotionalId,
          title: _title.text,
          summary: _summary.text,
          body: _body.text,
          scriptureRef: _scriptureRef.text,
          scriptureText: _scriptureText.text,
          category: _category,
          isPublished: _published,
        ),
        authorName: authorName,
      );

      ref
        ..invalidate(allDevotionalsProvider)
        ..invalidate(publishedDevotionalsProvider)
        ..invalidate(adminMetricsProvider);
      if (widget.devotionalId != null) {
        ref.invalidate(devotionalProvider(widget.devotionalId!));
      }

      if (!mounted) return;
      showAppSnackBar(
        context,
        _published
            ? '"${saved.title}" saved and published.'
            : '"${saved.title}" saved as a draft.',
      );
      context.pop();
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The devotional didn't save.",
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

    if (!_isEdit) return _form(context, theme);

    final existing = ref.watch(devotionalProvider(widget.devotionalId!));
    return AsyncView<Devotional>(
      value: existing,
      onRetry: () => ref.invalidate(devotionalProvider(widget.devotionalId!)),
      loading: const AdminPage(
        title: 'Edit devotional',
        showBack: true,
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              children: [
                SkeletonBox(height: 56),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 56),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 160),
              ],
            ),
          ),
        ),
      ),
      data: (item) {
        if (!_seeded) {
          _seeded = true;
          _title.text = item.title;
          _summary.text = item.summary;
          _body.text = item.body;
          _scriptureRef.text = item.scriptureRef;
          _scriptureText.text = item.scriptureText;
          _category = item.category;
          _published = item.isPublished;
        }
        return _form(context, theme);
      },
    );
  }

  Widget _form(BuildContext context, ThemeData theme) {
    return AdminPage(
      title: _isEdit ? 'Edit devotional' : 'New devotional',
      subtitle: _published ? 'Publishing to the shelf' : 'Saving as a draft',
      showBack: true,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give it a title.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _summary,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Summary',
                helperText: 'One line, shown on the browse card.',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Write the one-line summary members will see.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            Text('Category', style: theme.textTheme.labelMedium),
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
              controller: _body,
              minLines: 8,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Body',
                helperText: 'Separate paragraphs with a blank line.',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().length < 20)
                  ? 'The body needs at least a short paragraph.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            const SectionHeader(
              title: 'Scripture',
              subtitle: 'Optional. Leave both blank for a prompt with no passage.',
              dense: true,
            ),
            TextFormField(
              controller: _scriptureRef,
              decoration: const InputDecoration(
                labelText: 'Reference',
                hintText: 'Psalm 121:1-2',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _scriptureText,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Passage',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                final hasRef = _scriptureRef.text.trim().isNotEmpty;
                final hasText = (value ?? '').trim().isNotEmpty;
                if (hasRef && !hasText) {
                  return 'Add the passage, or clear the reference.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xl),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('Published', style: theme.textTheme.titleSmall),
              subtitle: Text(
                _published
                    ? 'Live on the member shelf.'
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
