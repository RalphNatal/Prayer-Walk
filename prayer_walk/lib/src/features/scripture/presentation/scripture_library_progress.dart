import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/app_logger.dart';
import '../data/scripture_history_controller.dart';
import '../data/scripture_providers.dart';

/// How much of the library this member has been given, and the way back to the
/// start of it.
///
/// Shown because the freshness rules are otherwise invisible. A member whose
/// verses stopped repeating has no way of knowing whether that is because the
/// library is enormous or because the app is remembering — and a member who has
/// worked through the whole thing deserves to be told that, rather than
/// noticing passages coming round again and assuming something broke.
///
/// The reset is here for the opposite reason. Not everybody wants novelty:
/// somebody who has spent a season with these passages may well want to walk
/// them again deliberately, and "the app decides you have had this one" is a
/// bad answer to that.
class ScriptureLibraryProgress extends ConsumerWidget {
  const ScriptureLibraryProgress({super.key, this.allowReset = true});

  /// Whether "Start the library fresh" is offered here.
  ///
  /// False in the sheet the record screen opens, where somebody is a tap away
  /// from starting a walk and is not there to make an irreversible decision
  /// about months of history. The progress line itself is welcome in both
  /// places; the destructive control belongs where it can be arrived at
  /// deliberately.
  final bool allowReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(scriptureHistoryProvider);
    // The library resolves through the cache and the bundled asset, so this has
    // a number offline too. While it is still resolving there is nothing
    // truthful to say about a total, so the line waits rather than guessing.
    final library = ref.watch(scriptureLibraryProvider).value;

    if (library == null || library.isEmpty) return const SizedBox.shrink();

    // Clamped because the two numbers come from different places: history can
    // hold passages an admin has since unpublished, and "39 of 38" would be a
    // true statement that reads as a bug.
    final total = library.length;
    final received = history.seenCount.clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your library', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          received == 0
              ? 'You have $total passages ahead of you.'
              : "You've received $received of $total passages.",
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          received >= total
              ? 'You have walked the whole library. Passages will come round '
                    'again now, longest-unseen first.'
              : 'Passages you have not had yet come first, and one you have '
                    'had recently waits its turn.',
          style: theme.textTheme.bodySmall,
        ),
        if (allowReset && received > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _confirmReset(context, ref),
              child: const Text('Start the library fresh'),
            ),
          ),
        ],
      ],
    );
  }

  /// Confirmed, because it cannot be undone: the record of what somebody has
  /// read over months of walking is not something to lose to a mis-tap.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start the library fresh?'),
        content: const Text(
          'Every passage becomes new again, and they will start arriving in a '
          'fresh order from your next walk. What you have already walked is '
          'not affected — only the record of which passages you have been '
          'given.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scriptureHistoryProvider.notifier).reset();
      messenger.showSnackBar(
        const SnackBar(content: Text('The library is fresh again.')),
      );
    } catch (error) {
      // Unlike everything else in scripture delivery, this one reports. It was
      // asked for deliberately and confirmed, and the server copy would hand
      // the history straight back at the next sign-in — so saying nothing would
      // be telling somebody it worked when it did not.
      AppLogger.warn('PW-SCRIP', 'could not clear delivery history', error);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not clear your history just now. Try again when you have a '
            'connection.',
          ),
        ),
      );
    }
  }
}
