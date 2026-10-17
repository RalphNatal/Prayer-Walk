import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import '../domain/church_group_fields.dart';
import 'widgets/church_group_tile.dart';
import 'widgets/group_avatar.dart';

const _tag = 'PW-GROUPS';

/// Joining a group someone gave you a code for — the only way into a hidden
/// group, and a shortcut into any other.
///
/// Two steps on purpose: the code is checked and the group shown before
/// anything is joined, so a mistyped code that happens to match some other
/// church does not quietly add its scripture to every walk.
Future<void> showJoinWithCodeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _JoinWithCodeSheet(),
  );
}

class _JoinWithCodeSheet extends ConsumerStatefulWidget {
  const _JoinWithCodeSheet();

  @override
  ConsumerState<_JoinWithCodeSheet> createState() => _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends ConsumerState<_JoinWithCodeSheet> {
  final _code = TextEditingController();
  ChurchGroup? _found;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    if (!isCompleteInviteCode(_code.text)) {
      setState(() => _error = 'Codes are twelve letters and numbers.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await ref
          .read(churchGroupRepositoryProvider)
          .previewByCode(_code.text);
      if (!mounted) return;
      setState(() {
        _found = group;
        _error = group == null
            ? "That code doesn't match a group. Check it with whoever shared "
                  'it — an admin can make a new one.'
            : null;
      });
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That code couldn't be checked.",
          onRetry: _lookUp,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final group = await ref
          .read(churchGroupActionsProvider)
          .joinWithCode(_code.text);
      if (!mounted) return;
      final router = GoRouter.of(context);
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            group.isPending
                ? 'Request sent to ${group.name}.'
                : 'Welcome to ${group.name}.',
          ),
        ),
      );
      router.pushNamed(
        Routes.churchGroup,
        pathParameters: {'groupId': group.id},
      );
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "You weren't added to that group.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _found;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Join with a code',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A group admin can share a code from their group page. Some '
              'groups are only reachable this way.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _code,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                if (_found != null || _error != null) {
                  setState(() {
                    _found = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _lookUp(),
              decoration: InputDecoration(
                labelText: 'Invite code',
                hintText: '7F3A-91C2-0B4E',
                errorText: _error,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: AppMotion.standard,
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              child: found == null
                  ? PrimaryButton(
                      key: const ValueKey('look-up'),
                      label: 'Find group',
                      icon: Icons.search_rounded,
                      expand: true,
                      busy: _busy,
                      onPressed: _lookUp,
                    )
                  : _Preview(
                      key: ValueKey(found.id),
                      group: found,
                      busy: _busy,
                      onJoin: _join,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    super.key,
    required this.group,
    required this.busy,
    required this.onJoin,
  });

  final ChurchGroup group;
  final bool busy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final already = !group.canJoin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.control,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              ChurchGroupAvatar(group: group, outlined: false),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: theme.textTheme.titleSmall),
                    Text(
                      [
                        if (group.city.isNotEmpty) group.city,
                        memberCountLabel(group.memberCount),
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (already)
          Text(
            group.isBanned
                ? "You can't rejoin this group."
                : "You're already in this group.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else
          PrimaryButton(
            label: group.joinPolicy == GroupJoinPolicy.request
                ? 'Ask to join'
                : 'Join ${group.name}',
            icon: Icons.add_rounded,
            expand: true,
            large: true,
            busy: busy,
            onPressed: onJoin,
          ),
      ],
    );
  }
}
