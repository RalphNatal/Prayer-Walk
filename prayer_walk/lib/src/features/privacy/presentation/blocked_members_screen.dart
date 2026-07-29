import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/domain/user_profile.dart';
import '../data/privacy_actions.dart';
import '../data/privacy_providers.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-BLOCK';

/// Who has been shut out, and the way back.
///
/// Deliberately reversible and deliberately quiet. A block list that reads like
/// an enemies list invites people to curate it; this one is a utility, and the
/// only action on a row is to undo it.
class BlockedMembersScreen extends ConsumerWidget {
  const BlockedMembersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    UserProfile person,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Unblock ${person.displayName}?',
      message:
          'They will be able to see your public walks and follow you again. '
          'Any follow between you was removed when you blocked them and does '
          'not come back on its own.',
      confirmLabel: 'Unblock',
    );
    if (!confirmed) return;

    try {
      await ref.read(privacyActionsProvider).toggleBlock(person.id);
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
      return;
    }
    if (context.mounted) {
      showAppSnackBar(context, '${person.displayName} unblocked.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked members')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(blockedMembersProvider.future),
        child: AsyncView<List<UserProfile>>(
          value: blocked,
          errorFallback: "That list couldn't be loaded.",
          onRetry: () => ref.invalidate(blockedMembersProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.lg),
            child: RowListLoading(count: 3),
          ),
          empty: () => const ScrollableStateBody(
            child: EmptyState(
              icon: Icons.block_rounded,
              title: 'Nobody blocked',
              message:
                  'You can block anyone from their profile. It takes effect '
                  'straight away and works in both directions.',
            ),
          ),
          data: (items) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final person = items[index];
              // No tap-through to the profile. Following a link to somebody you
              // have blocked is not a journey this screen should offer.
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                ),
                leading: UserAvatar(
                  initials: person.initials,
                  accentIndex: person.accentIndex,
                ),
                title: Text(person.displayName),
                subtitle: Text(person.handle),
                trailing: AppTextButton(
                  label: 'Unblock',
                  onPressed: () => _unblock(context, ref, person),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
