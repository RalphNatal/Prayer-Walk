import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../groups/presentation/churches_view.dart';
import '../data/discovery_providers.dart';
import '../domain/member_card.dart';
import 'member_tile.dart';
import 'suggested_members_strip.dart';

/// Which half of Discover is showing.
enum DiscoverTab { people, churches }

/// Finding people, and finding your church.
///
/// Two tabs under one door. Churches live here rather than in a bottom-bar tab
/// of their own: the bar already carries five destinations, and a church is
/// something you join once and then meet mostly through its scripture on your
/// walks — the same "a door, not a place to live" reasoning that keeps
/// Discover itself off the bar. See the note above `Routes.churchGroup`.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key, this.initialTab = DiscoverTab.people});

  final DiscoverTab initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: DiscoverTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discover'),
          bottom: TabBar(
            onTap: (_) => AppHaptics.selection(),
            tabs: const [
              Tab(text: 'People'),
              Tab(text: 'Churches'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Focus the field only on the tab somebody came for: a keyboard
            // springing up over the Churches tab would hide the list of
            // churches it opens on.
            PeopleSearchView(autofocus: initialTab == DiscoverTab.people),
            const ChurchesView(),
          ],
        ),
      ),
    );
  }
}

/// A1 · Finding people.
///
/// The door the community never had. Everything social in this app — following,
/// encouragement, comments, the follower counts on a profile — has existed and
/// been unreachable, because there was no way in the member app to find a single
/// person to follow.
///
/// A field, a list, and the suggestions strip underneath it while the field is
/// empty. Nothing is listed until somebody types: a directory that shows the
/// whole membership on focus has published a membership roll, which is a
/// different feature and not one this app has.
class PeopleSearchView extends ConsumerStatefulWidget {
  const PeopleSearchView({super.key, this.autofocus = true});

  final bool autofocus;

  @override
  ConsumerState<PeopleSearchView> createState() => _PeopleSearchViewState();
}

class _PeopleSearchViewState extends ConsumerState<PeopleSearchView> {
  final _field = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Coming back to Discover with a term still in the provider should show the
    // field the way it was left, not an empty box above somebody's results.
    _field.text = ref.read(memberSearchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  /// 300 ms, which is about the gap between two letters typed and well under
  /// the pause that reads as "I have finished typing". Searching on every
  /// keystroke would put six requests behind the word "Villanueva" and show
  /// five wrong answers on the way to the right one.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(memberSearchQueryProvider.notifier).set(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _field.clear();
    ref.read(memberSearchQueryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(memberSearchQueryProvider);
    final results = ref.watch(memberSearchProvider);
    final searching = query.trim().isNotEmpty;

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
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (value) =>
                ref.read(memberSearchQueryProvider.notifier).set(value),
            decoration: InputDecoration(
              hintText: 'Name, handle or church',
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
          child: searching
              ? _Results(results: results, query: query)
              : const _BeforeSearching(),
        ),
      ],
    );
  }
}

/// What Discover shows before a single letter is typed: the suggestions, and a
/// line saying what to do. Not an error, not a spinner, and not the membership.
class _BeforeSearching extends StatelessWidget {
  const _BeforeSearching();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.listBody,
      children: [
        const SuggestedMembersStrip(),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Search by name, by handle, or by church. People who have chosen to '
          'walk publicly appear above.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.results, required this.query});

  final AsyncValue<List<MemberCard>> results;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<List<MemberCard>>(
      value: results,
      errorFallback: "That search couldn't be run.",
      onRetry: () => ref.invalidate(memberSearchProvider),
      isEmpty: (items) => items.isEmpty,
      loading: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: RowListLoading(count: 5),
      ),
      empty: () => EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Nobody by that name',
        message:
            'Nothing matches "${query.trim()}". Try a surname, or the handle '
            'they gave you — it starts with an @.',
      ),
      data: (items) => ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => MemberTile(card: items[index]),
      ),
    );
  }
}
