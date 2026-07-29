import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics/schema_preflight_banner.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/scripture/data/scripture_history_controller.dart';

/// The root widget: theme in, router out.
class PrayerWalkApp extends ConsumerWidget {
  const PrayerWalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched for its side effect and nothing else: it pulls down the member's
    // scripture delivery record whenever they sign in, so a second phone does
    // not start the library again from zero. Here rather than on a screen
    // because it must happen on sign-in wherever that happened from, and must
    // not be undone by navigating away.
    ref.watch(scriptureHistorySyncProvider);

    return MaterialApp.router(
      title: 'Prayer Walk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeControllerProvider),
      routerConfig: ref.watch(routerProvider),
      // Above the router so it survives navigation, below `MaterialApp` so it
      // has a Directionality and an Overlay. Compiles to a passthrough in
      // release — see `SchemaPreflight.isEnabled`.
      builder: (context, child) =>
          SchemaPreflightBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}
