import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import 'join_with_code_sheet.dart';
import 'widgets/church_group_tile.dart';

/// The Churches tab of Discover: your churches first, then finding one.
///
/// Unlike people search, this lists groups before anything is typed. A person
/// has not asked to be listed and a directory of them would be a membership
/// roll; a church group that chose to be discoverable has asked for exactly
/// that, and an empty field over an empty page would be a dead end for the
/// one thing this tab is for.
class ChurchesView extends ConsumerStatefulWidget {
  const ChurchesView({super.key});

  @override
  ConsumerState<ChurchesView> createState() => _ChurchesViewState();
}

class _ChurchesViewState extends ConsumerState<ChurchesView> {
  final _field = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _field.text = ref.read(groupSearchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  /// The same 300 ms Discover's people search waits — see its comment.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(groupSearchQueryProvider.notifier).set(value);
    });
    setState(() {});
  }

  void _clear() {
    _debounce?.cancel();
    _field.clear();
    ref.read(groupSearchQueryProvider.notifier).clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final searching = _field.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: TextField(
            controller: _field,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (value) =>
                ref.read(groupSearchQueryProvider.notifier).set(value),
            decoration: InputDecoration(
              hintText: 'Church name or city',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searching
                  ? IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clear,
                    )
                  : null,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myGroupsProvider)
                ..invalidate(listedGroupsProvider)
                ..invalidate(groupSearchProvider);
              await ref.read(myGroupsProvider.future);
            },
            child: searching
                ? _SearchResults(query: _field.text.trim())
                : const _Browse(),
          ),
        ),
      ],
    );
  }
}

/// Before anything is typed: your churches, the two ways in, and the largest
/// groups on the app.
class _Browse extends ConsumerWidget {
  const _Browse();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myGroupsProvider);
    final listed = ref.watch(listedGroupsProvider);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.listBody,
      children: [
        const SectionHeader(title: 'Your churches'),
        AsyncView<List<ChurchGroup>>(
          value: mine,
          errorFallback: "Your churches couldn't be loaded.",
          onRetry: () => ref.invalidate(myGroupsProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const RowListLoading(count: 2, leadingSize: AppSizes.avatarMd),
          empty: () => const _NoChurchYet(),
          data: (items) => Column(
            children: [
              for (final group in items) ChurchGroupTile(group: group),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _WaysIn(),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          title: 'Churches on Prayer Walk',
          subtitle: 'Groups that chose to be listed, largest first.',
        ),
        AsyncView<List<ChurchGroup>>(
          value: listed,
          errorFallback: "Churches couldn't be loaded.",
          onRetry: () => ref.invalidate(listedGroupsProvider),
          isEmpty: (items) => items.isEmpty,
          loading: const RowListLoading(count: 4, leadingSize: AppSizes.avatarMd),
          empty: () => EmptyState(
            compact: true,
            icon: Icons.church_outlined,
            title: 'No churches listed yet',
            message:
                'Be the first: start a group for your church and the people '
                'you walk with can find it here.',
            actionLabel: 'Start a group',
            onAction: () => context.pushNamed(Routes.createChurchGroup),
          ),
          data: (items) => Column(
            children: [
              for (final group in items) ChurchGroupTile(group: group),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Your churches" with nothing in it — an invitation with somewhere to go.
class _NoChurchYet extends StatelessWidget {
  const _NoChurchYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.church_outlined, color: theme.colorScheme.secondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              "You haven't joined a church yet. Search for yours below, or "
              'start one — members receive their church\'s scripture on '
              'every walk.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The two ways into a group other than search.
class _WaysIn extends StatelessWidget {
  const _WaysIn();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        SecondaryButton(
          label: 'Start a group',
          icon: Icons.add_rounded,
          onPressed: () => context.pushNamed(Routes.createChurchGroup),
        ),
        SecondaryButton(
          label: 'Join with a code',
          icon: Icons.key_rounded,
          onPressed: () => showJoinWithCodeSheet(context),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<ChurchGroup>>(
      value: ref.watch(groupSearchProvider),
      errorFallback: "That search couldn't be run.",
      onRetry: () => ref.invalidate(groupSearchProvider),
      isEmpty: (items) => items.isEmpty,
      loading: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: RowListLoading(count: 5, leadingSize: AppSizes.avatarMd),
      ),
      empty: () => ScrollableStateBody(
        child: EmptyState(
          icon: Icons.church_outlined,
          title: 'No church by that name',
          message:
              'Nothing listed matches "$query". Try the town instead, or '
              'start a group for your church. Some groups are hidden and '
              'only open with a code.',
          actionLabel: 'Start a group',
          onAction: () => context.pushNamed(Routes.createChurchGroup),
          secondaryLabel: 'Join with a code',
          onSecondary: () => showJoinWithCodeSheet(context),
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
        itemBuilder: (context, index) => ChurchGroupTile(group: items[index]),
      ),
    );
  }
}
