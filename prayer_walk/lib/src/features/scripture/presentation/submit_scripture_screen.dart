import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../../devotionals/domain/devotional.dart' show DevotionalCategory;
import '../data/scripture_providers.dart';
import '../domain/scripture_prompt.dart';
import '../domain/scripture_submission.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-SUBMIT';

/// C1/C2 · A member proposing a verse or a prayer for other people's walks.
///
/// The form is deliberately shaped around what a member can give: a reference,
/// a theme, and a line in their own words about why this one. That last field
/// is the point of the screen, and it is the only required piece of writing —
/// see [ScriptureSubmissionDraft] for the licensing argument behind that shape.
///
/// The optional text field is public-domain only, and says so beside itself
/// rather than in a help page. The database refuses anything else; the copy is
/// there so nobody wastes their time typing an NLT passage that will bounce.
class SubmitScriptureScreen extends ConsumerStatefulWidget {
  const SubmitScriptureScreen({super.key});

  @override
  ConsumerState<SubmitScriptureScreen> createState() =>
      _SubmitScriptureScreenState();
}

class _SubmitScriptureScreenState
    extends ConsumerState<SubmitScriptureScreen> {
  final _reference = TextEditingController();
  final _body = TextEditingController();
  final _reflection = TextEditingController();

  ScripturePromptKind _kind = ScripturePromptKind.scripture;
  DevotionalCategory _category = DevotionalCategory.stillness;
  bool _sending = false;

  @override
  void dispose() {
    _reference.dispose();
    _body.dispose();
    _reflection.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(scriptureRepositoryProvider)
          .submitPrompt(
            ScriptureSubmissionDraft(
              reference: _reference.text,
              body: _body.text,
              reflection: _reflection.text,
              kind: _kind,
              category: _category,
            ),
          );
      ref
        ..invalidate(myScriptureSubmissionsProvider)
        ..invalidate(scriptureSubmissionsProvider)
        ..invalidate(pendingSubmissionCountProvider);
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Sent. A moderator will read it before it goes on any walk.',
      );
      context.pop();
    } on AppException catch (failure, stack) {
      // Already phrased for the person — say what it says, but never silently.
      AppLogger.warn(_tag, failure.message, failure, stack);
      if (mounted) showAppSnackBar(context, failure.message);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That didn't send. Your words are still here.",
          onRetry: _send,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isScripture = _kind == ScripturePromptKind.scripture;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suggest a prompt'),
        actions: [
          AppTextButton(
            label: 'Mine',
            onPressed: () =>
                context.pushNamed(Routes.myScriptureSubmissions),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: AppSpacing.listBody,
        children: [
          Text(
            'Prompts are read out on other people\'s walks. Suggest one, and a '
            'moderator will decide whether it joins the library.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),

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

          TextField(
            controller: _reference,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: isScripture ? 'Passage' : 'Name of the prayer',
              hintText: isScripture ? 'Psalm 121:1-2' : 'A prayer for the road',
              helperText: isScripture
                  ? 'Book, chapter and verse. The text itself is optional.'
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

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
          const SizedBox(height: AppSpacing.xxl),

          const SectionHeader(
            title: 'Your own words',
            subtitle:
                'A line about why this one. This is the part that makes it '
                'yours, and it travels with the verse.',
          ),
          TextField(
            controller: _reflection,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What this passage carries you through.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          if (isScripture) ...[
            const SectionHeader(
              title: 'The text (optional)',
              subtitle: 'Public domain only.',
            ),
            const _LicenceNote(),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _body,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText:
                    '${ScriptureSubmissionDraft.allowedTranslation.shortCode} '
                    'text',
                hintText:
                    'Leave blank and a moderator will match the reference.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],

          PrimaryButton(
            label: 'Send for review',
            expand: true,
            large: true,
            busy: _sending,
            onPressed: _send,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nothing is delivered on a walk until a moderator approves it. You '
            'can see what happened to yours under "Mine".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// ⚖️ The copyright position, stated beside the field it governs.
///
/// The rule is enforced by the insert policy on `scripture_prompts`, which
/// refuses any translation this app does not own outright. This paragraph
/// exists so that nobody types out a licensed passage in good faith and has it
/// bounce back at them with a Postgres code.
class _LicenceNote extends StatelessWidget {
  const _LicenceNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.balance_outlined,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              ScriptureSubmissionDraft.licenceNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
