import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../social/data/social_actions.dart';
import '../../social/presentation/optimistic_toggle.dart';
import '../data/discovery_providers.dart';
import '../domain/member_card.dart';

/// A3 · People to follow, along the top of an empty feed and of Discover.
///
/// One rule behind it, said on the header rather than left implicit: these are
/// the members who most recently posted a public walk. Nothing is scored, and
/// anybody who asks why they are being shown a particular person can be given a
/// true answer in a sentence.
///
/// Renders nothing at all while loading, on failure, or when there is nobody to
/// suggest — the same restraint the announcement banner shows. A strip of
/// skeletons above an empty feed is two absences stacked on each other.
class SuggestedMembersStrip extends ConsumerWidget {
  const SuggestedMembersStrip({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestedMembersProvider).value;
    if (suggestions == null || suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          const SectionHeader(
            title: 'People to follow',
            subtitle: 'Members who walked publicly most recently.',
          ),
        SizedBox(
          // A horizontal list has to be given a height, and this one holds
          // three lines of text and a button. A fixed number overflows the
          // moment somebody turns "larger text" on, so only the parts that do
          // not scale — the padding and the avatar — are fixed, and the rest is
          // asked for at whatever size the reader has chosen.
          height:
              76 + MediaQuery.textScalerOf(context).scale(105).clamp(105, 260),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) =>
                _SuggestionCard(card: suggestions[index]),
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.card});

  final MemberCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final person = card.profile;

    return SizedBox(
      width: 156,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.control,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: AppRadius.control,
          onTap: () => context.pushNamed(
            Routes.userProfile,
            pathParameters: {'userId': person.id},
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                UserAvatar(
                  initials: person.initials,
                  accentIndex: person.accentIndex,
                  imageUrl: person.avatarUrl,
                  size: AppSizes.avatarMd,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  person.parish.trim().isEmpty
                      ? person.handle
                      : person.parish.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                _FollowButton(card: card),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.card});

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
      builder: (context, isFollowing, _, toggle) => isFollowing
          ? SecondaryButton(
              label: 'Following',
              expand: true,
              onPressed: toggle,
            )
          : PrimaryButton(label: 'Follow', expand: true, onPressed: toggle),
    );
  }
}
