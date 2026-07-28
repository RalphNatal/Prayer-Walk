import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_spacing.dart';
import '../utils/app_haptics.dart';
import 'page_transitions.dart';

/// The member experience: five destinations, Record raised in the middle.
///
/// Record gets the amber block because starting a walk is the one thing this
/// app exists to make easy. It is still a [NavigationBar] destination rather
/// than a floating button, so it keeps the same selection semantics, focus
/// order and screen-reader behaviour as its neighbours.
class MemberShell extends StatelessWidget {
  const MemberShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = <_MemberDestination>[
    _MemberDestination('Home', Icons.home_outlined, Icons.home_rounded),
    _MemberDestination(
      'Devotionals',
      Icons.auto_stories_outlined,
      Icons.auto_stories_rounded,
    ),
    _MemberDestination(
      'Record',
      Icons.directions_walk_rounded,
      Icons.directions_walk_rounded,
      emphasised: true,
    ),
    _MemberDestination('History', Icons.route_outlined, Icons.route_rounded),
    _MemberDestination('Profile', Icons.person_outline, Icons.person_rounded),
  ];

  void _onDestinationSelected(int index) {
    AppHaptics.selection();
    navigationShell.goBranch(
      index,
      // Tapping the tab you are already on returns to the top of that branch.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Peers crossfade rather than cut. The indexed stack underneath is
      // untouched — each branch keeps its own navigator and scroll position.
      body: BranchFade(index: navigationShell.currentIndex, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          for (var i = 0; i < _destinations.length; i++)
            _destinations[i].build(
              context,
              selected: navigationShell.currentIndex == i,
            ),
        ],
      ),
    );
  }
}

class _MemberDestination {
  const _MemberDestination(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.emphasised = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool emphasised;

  NavigationDestination build(BuildContext context, {required bool selected}) {
    if (!emphasised) {
      return NavigationDestination(
        icon: Icon(icon),
        selectedIcon: Icon(selectedIcon),
        label: label,
        tooltip: label,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    Widget block(Color background, Color foreground) => Container(
      width: 46,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
      ),
      child: Icon(icon, size: 22, color: foreground),
    );

    return NavigationDestination(
      icon: block(scheme.tertiary, scheme.onTertiary),
      selectedIcon: block(scheme.primary, scheme.onPrimary),
      label: label,
      tooltip: 'Record a walk',
    );
  }
}
