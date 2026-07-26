import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/data/mock_admin_repository.dart';
import '../constants/app_spacing.dart';

/// Admin destinations, in nav order.
enum AdminDestination {
  dashboard('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded),
  members('Members', Icons.people_outline, Icons.people_rounded),
  content('Content', Icons.article_outlined, Icons.article_rounded),
  moderation('Moderation', Icons.flag_outlined, Icons.flag_rounded),
  announcements('Announcements', Icons.campaign_outlined, Icons.campaign_rounded),
  settings('Settings', Icons.settings_outlined, Icons.settings_rounded);

  const AdminDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Hands the branch switcher down to each admin page, so a page can build its
/// own [Scaffold] (and therefore its own drawer and app bar) while still
/// driving shell navigation.
class AdminShellScope extends InheritedWidget {
  const AdminShellScope({
    super.key,
    required this.navigationShell,
    required this.isWide,
    required super.child,
  });

  final StatefulNavigationShell navigationShell;

  /// True when the rail is showing, which means pages must not offer a drawer.
  final bool isWide;

  static AdminShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminShellScope>();

  void go(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  bool updateShouldNotify(AdminShellScope oldWidget) =>
      oldWidget.navigationShell != navigationShell || oldWidget.isWide != isWide;
}

/// The admin console shell: a rail from tablet width up, a drawer below it.
///
/// The console is deliberately plainer than the member app — denser rows,
/// smaller type, no trail flourishes. It is a tool for doing work, and it
/// should not compete with the thing it administers.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.wide;
        final isExtraWide = constraints.maxWidth >= AppBreakpoints.extraWide;

        return AdminShellScope(
          navigationShell: navigationShell,
          isWide: isWide,
          child: isWide
              ? Scaffold(
                  body: Row(
                    children: [
                      _AdminRail(
                        selectedIndex: navigationShell.currentIndex,
                        extended: isExtraWide,
                        onSelected: (i) => navigationShell.goBranch(
                          i,
                          initialLocation: i == navigationShell.currentIndex,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: navigationShell),
                    ],
                  ),
                )
              : navigationShell,
        );
      },
    );
  }
}

class _AdminRail extends ConsumerWidget {
  const _AdminRail({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  static const double _extendedWidth = 216;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = ref.watch(pendingReportCountProvider).value ?? 0;

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      extended: extended,
      minWidth: 84,
      minExtendedWidth: _extendedWidth,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.sm,
        ),
        // NavigationRail lays its leading widget out with unbounded width, so
        // the wordmark has to state its own.
        child: extended
            ? SizedBox(
                width: _extendedWidth - AppSpacing.lg * 2,
                child: Row(
                  children: [
                    const _AdminMark(),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        'Prayer Walk admin',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            : const _AdminMark(),
      ),
      destinations: [
        for (final destination in AdminDestination.values)
          NavigationRailDestination(
            icon: _RailIcon(
              icon: destination.icon,
              badge: destination == AdminDestination.moderation ? pending : 0,
            ),
            selectedIcon: _RailIcon(
              icon: destination.selectedIcon,
              badge: destination == AdminDestination.moderation ? pending : 0,
            ),
            label: Text(destination.label),
          ),
      ],
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon, required this.badge});

  final IconData icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0) return Icon(icon);
    return Badge.count(count: badge, child: Icon(icon));
  }
}

class _AdminMark extends StatelessWidget {
  const _AdminMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      ),
      child: Icon(Icons.terrain_rounded, size: 18, color: scheme.onPrimary),
    );
  }
}

/// The chrome every admin screen sits in.
///
/// Top-level pages get the drawer (narrow) or nothing (wide, the rail is
/// already there). Sub-pages get a back button instead.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.showBack = false,
    this.floatingActionButton,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AdminShellScope.maybeOf(context);
    final showDrawer = !showBack && (scope?.isWide == false);

    return Scaffold(
      drawer: showDrawer ? const AdminDrawer() : null,
      appBar: AppBar(
        // Resolves to the drawer button on narrow top-level pages and to the
        // back button on sub-pages, without either being wired by hand.
        titleSpacing: showBack || showDrawer ? 0 : AppSpacing.lg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [...actions, const SizedBox(width: AppSpacing.sm)],
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: body),
    );
  }
}

/// Branch navigation for narrow admin widths.
class AdminDrawer extends ConsumerWidget {
  const AdminDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scope = AdminShellScope.maybeOf(context);
    final selected = scope?.navigationShell.currentIndex ?? 0;
    final pending = ref.watch(pendingReportCountProvider).value ?? 0;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  const _AdminMark(),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prayer Walk', style: theme.textTheme.titleSmall),
                        Text('Admin console', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  for (var i = 0; i < AdminDestination.values.length; i++)
                    _DrawerTile(
                      destination: AdminDestination.values[i],
                      selected: i == selected,
                      badge: AdminDestination.values[i] ==
                              AdminDestination.moderation
                          ? pending
                          : 0,
                      onTap: () {
                        Navigator.of(context).pop();
                        scope?.go(i);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final AdminDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      selectedColor: scheme.onSurface,
      leading: Icon(selected ? destination.selectedIcon : destination.icon),
      title: Text(destination.label),
      trailing: badge > 0 ? Badge.count(count: badge) : null,
      onTap: onTap,
    );
  }
}
