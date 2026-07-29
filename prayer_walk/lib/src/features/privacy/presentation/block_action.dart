import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/widgets.dart';
import '../data/privacy_actions.dart';
import '../data/privacy_providers.dart';

/// Log tag for block failures.
const _tag = 'PW-BLOCK';

/// Blocking somebody, from wherever they are on screen.
///
/// Asks first, because it is not a gesture people expect to be able to make by
/// accident, and states both halves of what happens — this is the one control
/// in the app that removes a relationship rather than merely muting it, and the
/// follow rows go with it.
///
/// Returns whether [otherId] is now blocked, or null if the person backed out.
Future<bool?> confirmBlock(
  BuildContext context,
  WidgetRef ref, {
  required String otherId,
  required String name,
}) async {
  final alreadyBlocked = await ref.read(isBlockedProvider(otherId).future);
  if (!context.mounted) return null;

  final confirmed = await showConfirmDialog(
    context,
    title: alreadyBlocked ? 'Unblock $name?' : 'Block $name?',
    message: alreadyBlocked
        ? 'They will be able to see your public walks and follow you again.'
        : '$name will not be able to see your walks or your profile, follow '
              'you, encourage a walk of yours, or write on one — and you will '
              'not see theirs. If either of you follows the other, that ends '
              'now. You can undo this from Settings.',
    confirmLabel: alreadyBlocked ? 'Unblock' : 'Block',
    destructive: !alreadyBlocked,
  );
  if (!confirmed) return null;

  bool? nowBlocked;
  try {
    nowBlocked = await ref.read(privacyActionsProvider).toggleBlock(otherId);
  } catch (error, stack) {
    if (context.mounted) {
      reportFailure(
        context,
        error,
        stack,
        tag: _tag,
        fallback: "That didn't go through.",
      );
    }
    return null;
  }

  if (context.mounted && nowBlocked != null) {
    showAppSnackBar(
      context,
      nowBlocked ? '$name blocked.' : '$name unblocked.',
    );
  }
  return nowBlocked;
}
