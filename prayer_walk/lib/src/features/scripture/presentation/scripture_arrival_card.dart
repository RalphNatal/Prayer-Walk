import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/motion.dart';
import '../domain/scripture_settings.dart';
import 'scripture_reading.dart';

/// A verse arriving, without taking the screen.
///
/// This widget is where "do not block the walker" is actually enforced. It is
/// not a dialog, it is not modal, it has no button that must be pressed, and it
/// leaves on its own after [_dwell] whether or not anybody looked at it.
/// Ignoring it costs nothing; tapping it opens the whole passage. The walker is
/// on a road, and the road outranks the app.
///
/// Under reduced motion it appears rather than slides — the verse is the
/// information, the movement is only manners.
class ScriptureArrivalCard extends StatefulWidget {
  const ScriptureArrivalCard({
    super.key,
    required this.delivered,
    required this.showTranslation,
    required this.muted,
    required this.onToggleMute,
    required this.onDismiss,
  });

  final DeliveredPrompt delivered;
  final bool showTranslation;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onDismiss;

  /// Long enough to read two lines at walking pace, short enough that it is
  /// gone before it becomes something to deal with.
  static const _dwell = Duration(seconds: 12);

  @override
  State<ScriptureArrivalCard> createState() => _ScriptureArrivalCardState();
}

class _ScriptureArrivalCardState extends State<ScriptureArrivalCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
  );
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _restartDwell();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The reduced-motion query is a MediaQuery lookup, which is not readable
    // until dependencies are in place — so the entry plays from here rather
    // than from initState. The guard keeps an unrelated dependency change (a
    // theme switch mid-walk) from replaying it.
    if (_entry.value == 0 && !_entry.isAnimating) _playEntry();
  }

  @override
  void didUpdateWidget(ScriptureArrivalCard old) {
    super.didUpdateWidget(old);
    // A second verse while the first is still on screen replaces it and starts
    // its own dwell, rather than inheriting the remains of one.
    if (identical(old.delivered, widget.delivered)) return;
    _restartDwell();
    _playEntry();
  }

  /// The card leaves on its own. Nobody has to deal with it.
  void _restartDwell() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(ScriptureArrivalCard._dwell, () {
      if (mounted) widget.onDismiss();
    });
  }

  void _playEntry() {
    if (context.reduceMotion) {
      _entry.value = 1;
    } else {
      _entry.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.delivered.prompt;

    final card = Semantics(
      // The card announces itself to a screen reader as a live region, which is
      // the mechanism the platform actually prefers over a fired announcement.
      liveRegion: true,
      label: prompt.spoken,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showScriptureReading(
            context,
            prompt,
            showTranslation: widget.showTranslation,
          ),
          borderRadius: AppRadius.card,
          child: Ink(
            decoration: BoxDecoration(
              // Nearly opaque rather than a frosted tint: this sits over map
              // tiles that can be any colour, and the text has to clear contrast
              // over all of them.
              color: theme.colorScheme.surfaceContainerLowest.withValues(
                alpha: 0.97,
              ),
              borderRadius: AppRadius.card,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.22),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 15,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'On the trail',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                    // One tap, always in the same place, for the walker who
                    // wants the reading to stop talking.
                    //
                    // Both of these are hit mid-stride, one-handed, on a phone
                    // that is moving — which is exactly why they keep the full
                    // 48dp target and only the icon inside it is small. They
                    // used to be `visualDensity.compact`, i.e. 40dp.
                    IconButton(
                      onPressed: widget.onToggleMute,
                      iconSize: 20,
                      tooltip: widget.muted
                          ? 'Unmute scripture'
                          : 'Mute scripture',
                      icon: Icon(
                        widget.muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onDismiss,
                      iconSize: 20,
                      tooltip: 'Let it go',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ScriptureBody(
                    prompt: prompt,
                    showTranslation: widget.showTranslation,
                    maxLines: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_entry.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
        );
      },
      child: card,
    );
  }
}
