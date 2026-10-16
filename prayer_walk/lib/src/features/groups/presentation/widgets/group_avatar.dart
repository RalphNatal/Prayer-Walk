import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/church_group.dart';

/// A church group's picture, or its initials on a theme tint.
///
/// [UserAvatar]'s arrangement — lettered base layer, photo painted over it,
/// the same six container pairs — in a rounded square rather than a circle.
/// The shape is the whole point of the difference: a list that mixes people
/// and churches should never make somebody read a church as a person, or the
/// other way round.
class ChurchGroupAvatar extends StatelessWidget {
  const ChurchGroupAvatar({
    super.key,
    required this.group,
    this.size = AppSizes.avatarMd,
    this.outlined = true,
  });

  final ChurchGroup group;
  final double size;

  /// A surface-coloured border, for an avatar sitting over the cover.
  final bool outlined;

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
    final (background, foreground) =
        pairs[group.accentIndex.abs() % pairs.length];
    final radius = BorderRadius.circular(size * 0.24);
    final url = group.avatarUrl;

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(
            color: outlined ? scheme.surface : scheme.outlineVariant,
            width: outlined ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  group.initials,
                  style: AppTypography.display(
                    TextStyle(
                      color: foreground,
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
              if (url != null)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  frameBuilder: (context, child, frame, wasSynchronous) {
                    if (wasSynchronous) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: AppMotion.quick,
                      curve: AppMotion.enter,
                      child: child,
                    );
                  },
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The band across the top of a group's page.
///
/// The uploaded cover when there is one. When there is not — which is every
/// group on the day it starts — the painted ground the trail previews sit on,
/// with a faint contour, so an imageless group still looks like it belongs to
/// this app rather than like a missing picture.
class ChurchGroupCover extends StatelessWidget {
  const ChurchGroupCover({super.key, required this.group});

  final ChurchGroup group;

  @override
  Widget build(BuildContext context) {
    final trail = Theme.of(context).trail;
    final url = group.coverUrl;

    return AspectRatio(
      aspectRatio: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [trail.groundTop, trail.groundBottom],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _ContourPainter(trail.contour)),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                frameBuilder: (context, child, frame, wasSynchronous) {
                  if (wasSynchronous) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppMotion.standard,
                    curve: AppMotion.enter,
                    child: child,
                  );
                },
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Three soft contour lines, the cover's stand-in for a photograph.
class _ContourPainter extends CustomPainter {
  const _ContourPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.38 + i * 0.2);
      final path = Path()..moveTo(0, y);
      path.cubicTo(
        size.width * 0.3,
        y - size.height * 0.18,
        size.width * 0.62,
        y + size.height * 0.16,
        size.width,
        y - size.height * 0.06,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ContourPainter oldDelegate) => oldDelegate.color != color;
}
