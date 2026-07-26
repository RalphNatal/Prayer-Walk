import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/widgets.dart';
import 'routes.dart';

/// Shown when a deep link points at nothing.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Off the map')),
      body: Center(
        child: EmptyState(
          icon: Icons.explore_off_outlined,
          title: 'Nothing here',
          message: '$location does not lead anywhere. Head back to your feed.',
          actionLabel: 'Go to feed',
          onAction: () => context.goNamed(Routes.feed),
        ),
      ),
    );
  }
}
