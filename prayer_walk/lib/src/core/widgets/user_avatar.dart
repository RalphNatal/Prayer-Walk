import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// A member's photo, or their initials on a theme-derived tint.
///
/// The typographic avatar is not a placeholder to be replaced — it is the
/// avatar for everyone who has not uploaded a photo, which is every account on
/// the day it is made and plenty of them permanently. So it is drawn first and
/// always, and [imageUrl] paints over it. The tint comes from the colour
/// scheme's container pairs rather than raw hex, which means every combination
/// clears contrast in both themes for free.
///
/// Nothing here fetches a third-party URL. `UserProfile.avatarUrl` is null
/// unless it points into this project's own `avatars` bucket — the mapper
/// enforces that — so a face on a feed card never turns into a request to
/// somebody else's server.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.initials,
    required this.accentIndex,
    this.imageUrl,
    this.size = AppSizes.avatarMd,
    this.ring = false,
    this.semanticLabel,
  });

  final String initials;
  final int accentIndex;

  /// The uploaded photo. Null — or a URL that fails to load — leaves the
  /// initials showing, which is why they are the base layer rather than a
  /// branch.
  final String? imageUrl;

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

    final url = imageUrl;

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
        // The initials sit underneath the photo rather than beside it in an
        // if/else, so they are what shows while it loads and what is left if it
        // never does. A hole where a face goes reads as breakage; a lettered
        // circle reads as somebody who has not picked a picture.
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            Center(
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
            if (url != null)
              ClipOval(
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  // Stored square at 512px and drawn at 40-96. Decoding to the
                  // size it is actually painted at is the difference between a
                  // feed of twenty faces costing ~1 MB of image cache and
                  // ~20 MB. `ceil` on the physical pixels, so it is never
                  // decoded softer than the screen can show.
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  // A quiet cross-fade over the initials. Without it the letters
                  // visibly pop out as the photo lands, on every card, every
                  // time the list rebuilds.
                  frameBuilder: (context, child, frame, wasSynchronous) {
                    if (wasSynchronous) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  // No error copy and no retry: the initials underneath are
                  // already a correct avatar, and a broken-image glyph on a
                  // byline would be noise about something the member cannot act
                  // on.
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
