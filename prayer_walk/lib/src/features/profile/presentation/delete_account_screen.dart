import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_repository.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-DELETE';

const _confirmWord = 'DELETE';

/// Settings → Delete account.
///
/// A full screen rather than a dialog on top of [showConfirmDialog]: this is
/// the one destructive action in the app with its own progress state and its
/// own explanation, and a dialog has room for neither. Everything else about
/// it — the destructive styling, the "ask before something irreversible"
/// posture — matches [showConfirmDialog] and `block_action.dart`'s
/// `confirmBlock`; only the shape is different.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _deleting = false;
  bool _exporting = false;

  bool get _confirmed =>
      _confirmController.text.trim().toUpperCase() == _confirmWord;

  @override
  void initState() {
    super.initState();
    // The confirm button's enabled state is derived straight from the field,
    // so it has to hear every keystroke, not just submission.
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _exportData() async {
    setState(() => _exporting = true);
    try {
      final data = await ref.read(authRepositoryProvider).exportData();
      if (mounted) await _showExportDialog(context, data);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "Your data didn't export.",
          onRetry: _exportData,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    if (!_confirmed) return;
    setState(() => _deleting = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // Success falls through without touching state: the auth-state
      // redirect takes the screen away as soon as the sign-out above lands,
      // and a `setState` on an about-to-unmount widget is not needed.
    } catch (error, stack) {
      if (!mounted) return;
      reportFailure(
        context,
        error,
        stack,
        tag: _tag,
        fallback: "Your account wasn't deleted.",
        onRetry: _delete,
      );
      setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _deleting || _exporting;

    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'This permanently deletes your account and everything tied to '
            'it. There is no undo.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _BulletList(
            items: [
              'Your profile, and your sign-in.',
              'Every walk you recorded, and its route.',
              'Your follows and followers, and anyone you blocked.',
              'Encouragements and comments you left, and comments on your '
                  'walks.',
              'Your privacy zones and scripture delivery history.',
              'Your profile photo.',
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'A devotional or announcement you published for your parish '
            'keeps its byline text — the way an article outlives its '
            'author — but is no longer linked to your account in any way.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          OutlinedButton.icon(
            onPressed: busy ? null : _exportData,
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(_exporting ? 'Preparing…' : 'Export your data first'),
          ),
          const SizedBox(height: AppSpacing.xxl),

          Text(
            'Type $_confirmWord to confirm.',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _confirmController,
            enabled: !busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: _confirmWord,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!_confirmed || busy) ? null : _delete,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                minimumSize: const Size(0, 52),
              ),
              child: _deleting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.onError,
                      ),
                    )
                  : const Text('Delete my account'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: Text(item, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The exported data, viewable and copyable, but never written to a file —
/// the app has no file-share dependency, so this is the cheap-and-honest
/// version of "export": read it, or copy it out to wherever it needs to go.
Future<void> _showExportDialog(
  BuildContext context,
  Map<String, dynamic> data,
) {
  final pretty = const JsonEncoder.withIndent('  ').convert(data);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Your data'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(
          child: SelectableText(
            pretty,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pretty));
            if (!dialogContext.mounted) return;
            showAppSnackBar(dialogContext, 'Copied to clipboard.');
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
