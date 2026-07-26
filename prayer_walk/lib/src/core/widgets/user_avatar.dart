import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Initials on a theme-derived tint.
///
/// No photo uploads this phase, so the avatar is typographic. The tint comes
/// from the colour scheme's container pairs rather than raw hex, which means
/// every combination clears contrast in both themes for free.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.initials,
    required this.accentIndex,
    this.size = AppSizes.avatarMd,
    this.ring = false,
    this.semanticLabel,
  });

  final String initials;
  final int accentIndex;
  final double size;

  /// An amber ring — used to mark the signed-in person's own card.
  final bool ring;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairs = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.surfaceContainerHighest, scheme.onSurface),
      (scheme.errorContainer, scheme.onErrorContainer),
      (scheme.inverseSurface, scheme.onInverseSurface),
    ];
    final (background, foreground) = pairs[accentIndex.abs() % pairs.length];

    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: ring
              ? Border.all(color: scheme.tertiary, width: 2)
              : Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          initials,
          style: TextStyle(
            color: foreground,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}
