import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state_views.dart';

/// Renders the four states every list in this app has to handle: loading,
/// error, empty, and content.
///
/// Screens pass an [AsyncValue] and get all four for free, which is the point —
/// the states are guaranteed to exist rather than depending on whoever wrote
/// the screen remembering them.
///
/// While refreshing over existing data the previous content stays on screen;
/// only a first load shows the skeleton.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    required this.loading,
    this.isEmpty,
    this.empty,
    this.onRetry,
    this.errorFallback = "That didn't load.",
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;

  /// Shown on first load only — a skeleton shaped like the content.
  final Widget loading;

  /// Decides whether resolved data counts as empty. Usually `(l) => l.isEmpty`.
  final bool Function(T value)? isEmpty;
  final Widget Function()? empty;
  final VoidCallback? onRetry;

  /// The line shown when the load fails for a reason the mapper cannot name.
  /// Should say what this screen could not do — "Devotionals couldn't be
  /// loaded." — so the failure identifies itself without the person having to
  /// remember which screen they were on.
  final String errorFallback;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final resolved = value.requireValue;
      if (isEmpty?.call(resolved) ?? false) {
        return empty?.call() ?? const SizedBox.shrink();
      }
      return data(resolved);
    }
    if (value.hasError) {
      return ErrorStateView(
        error: value.error!,
        onRetry: onRetry,
        fallback: errorFallback,
      );
    }
    return loading;
  }
}

/// The same, for screens whose body must stay scrollable so pull-to-refresh
/// keeps working over an empty or failed list.
class ScrollableStateBody extends StatelessWidget {
  const ScrollableStateBody({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}
