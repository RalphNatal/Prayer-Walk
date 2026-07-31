import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../social/data/social_actions.dart';
import '../../social/presentation/optimistic_toggle.dart';
import '../domain/member_card.dart';

/// One person, with the Follow button on the row.
///
/// The button is here rather than one screen further in because that is the
/// difference between finding somebody and following them. `member_card` brings
/// `is_following` back with the search result precisely so this can be offered
/// without a second query per row.
class MemberTile extends ConsumerWidget {
  const MemberTile({super.key, required this.card});

  final MemberCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final person = card.profile;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      leading: UserAvatar(
        initials: person.initials,
        accentIndex: person.accentIndex,
        imageUrl: person.avatarUrl,
      ),
      title: Text(person.displayName),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: _FollowChip(card: card),
      onTap: () => context.pushNamed(
        Routes.userProfile,
        pathParameters: {'userId': person.id},
      ),
    );
  }

  /// Parish, then handle, then when they were last out — in that order,
  /// because "Our Lady of Peace, Antipolo" is what makes a stranger placeable
  /// and a handle is only a name with an @ in front of it.
  String _subtitle() {
    final person = card.profile;
    final parts = <String>[
      if (person.parish.trim().isNotEmpty) person.parish.trim() else person.handle,
      if (card.lastWalkedAt != null)
        'walked ${Fmt.relativeTime(card.lastWalkedAt!)}',
    ];
    return parts.join('  ·  ');
  }
}

class _FollowChip extends ConsumerWidget {
  const _FollowChip({required this.card});

  final MemberCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = card.profile.displayName;

    return OptimisticToggle(
      value: card.isFollowing,
      onToggle: () async {
        final nowFollowing = await ref
            .read(socialActionsProvider)
            .toggleFollow(card.profile.id);
        if (nowFollowing != null && context.mounted) {
          showAppSnackBar(
            context,
            nowFollowing ? 'Following $name.' : 'Unfollowed $name.',
          );
        }
        return nowFollowing;
      },
      onFailure: (error, stack) => reportFailure(
        context,
        error,
        stack,
        tag: 'PW-FOLLOW',
        fallback: "That didn't go through.",
      ),
      builder: (context, isFollowing, _, toggle) {
        if (isFollowing) {
          return AppTextButton(
            label: 'Following',
            icon: Icons.check_rounded,
            onPressed: toggle,
          );
        }
        return AppTextButton(
          label: 'Follow',
          icon: Icons.add_rounded,
          onPressed: toggle,
        );
      },
    );
  }
}
