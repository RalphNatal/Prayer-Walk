import 'package:flutter/material.dart';

/// A two-state social toggle that answers instantly and takes it back if the
/// server disagrees.
///
/// Encouraging a walk and following a person are both a tap that should look
/// done before the round trip finishes. The dishonest version of that is a
/// button that flips and stays flipped whatever happens; this one flips, waits,
/// and reverts — with a sentence — when the write fails.
///
/// [value] is the truth from the server. While a write is in flight the
/// optimistic answer wins; it is dropped the moment the provider catches up
/// (avoiding the flicker of falling back to a stale value first), or on failure.
class OptimisticToggle extends StatefulWidget {
  const OptimisticToggle({
    super.key,
    required this.value,
    required this.onToggle,
    required this.builder,
    this.onFailure,
  });

  /// The server's answer, as last read.
  final bool value;

  /// Performs the write. Returns the state the server settled on, or null if
  /// nothing happened (signed out). Throwing means the toggle reverts.
  final Future<bool?> Function() onToggle;

  /// [value] is what to render; [delta] is `+1`, `-1` or `0` to apply to any
  /// count sitting beside the toggle, so the number moves with the button.
  final Widget Function(
    BuildContext context,
    bool value,
    int delta,
    VoidCallback toggle,
  )
  builder;

  /// Told what actually went wrong, stack and all — a reverted toggle is a
  /// failure like any other and gets reported like one.
  final void Function(Object error, StackTrace stackTrace)? onFailure;

  @override
  State<OptimisticToggle> createState() => _OptimisticToggleState();
}

class _OptimisticToggleState extends State<OptimisticToggle> {
  /// The answer we are showing ahead of the server. Null means "show [value]".
  bool? _pending;

  bool get _effective => _pending ?? widget.value;

  int get _delta => _pending == null || _pending == widget.value
      ? 0
      : (_pending! ? 1 : -1);

  @override
  void didUpdateWidget(OptimisticToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The server caught up with us — stop overriding it.
    if (_pending != null && widget.value == _pending) {
      _pending = null;
    }
  }

  Future<void> _toggle() async {
    if (_pending != null) return; // A write is already in flight.
    final next = !_effective;
    setState(() => _pending = next);

    try {
      final settled = await widget.onToggle();
      if (!mounted) return;
      if (settled == null) {
        setState(() => _pending = null);
      } else if (settled != next) {
        // The server went the other way — a double tap elsewhere, or a row
        // that was already there. Show what is actually true.
        setState(() => _pending = settled);
      }
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _pending = null);
      widget.onFailure?.call(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _effective, _delta, _toggle);
}
