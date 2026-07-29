import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../activity/data/recording_controller.dart';
import '../../scripture/presentation/scripture_quotation.dart';
import '../data/devotional_providers.dart';
import '../domain/devotional.dart';

/// Read a devotional, then take it out with you.
class DevotionalReaderScreen extends ConsumerWidget {
  const DevotionalReaderScreen({super.key, required this.devotionalId});

  final String devotionalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devotional = ref.watch(devotionalProvider(devotionalId));

    return Scaffold(
      appBar: AppBar(title: const Text('Devotional')),
      body: AsyncView<Devotional>(
        value: devotional,
        errorFallback: "This devotional couldn't be opened.",
        onRetry: () => ref.invalidate(devotionalProvider(devotionalId)),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 32, width: 260),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox.line(width: 160),
                SizedBox(height: AppSpacing.xxl),
                SkeletonBox(height: 96),
                SizedBox(height: AppSpacing.xl),
                SkeletonBox.line(),
                SizedBox(height: AppSpacing.md),
                SkeletonBox.line(),
                SizedBox(height: AppSpacing.md),
                SkeletonBox.line(width: 220),
              ],
            ),
          ),
        ),
        data: (item) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    // Measure caps at a comfortable reading line length.
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.category.label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(item.title, style: theme.textTheme.displaySmall),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${item.authorName}  ·  ${item.readMinutes} min read',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (item.hasScripture) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _ScriptureBlock(devotional: item),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        for (final paragraph in item.body.split('\n\n'))
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.lg,
                            ),
                            child: Text(
                              paragraph.trim(),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _ReaderFooter(devotional: item),
          ],
        ),
      ),
    );
  }
}

/// The passage, pulled out of the page.
///
/// The quotation goes through [ScriptureQuotation] rather than a bare [Text]
/// for the same reason the arrival card does: a licensed edition's mark travels
/// with the words, and the reader is the one screen where a passage is quoted at
/// full size.
class _ScriptureBlock extends StatelessWidget {
  const _ScriptureBlock({required this.devotional});

  final Devotional devotional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border(
          left: BorderSide(color: theme.colorScheme.tertiary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScriptureQuotation(
            text: devotional.scriptureText,
            translationId: devotional.translation,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Flexible(
                child: Text(
                  devotional.scriptureRef,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
              if (devotional.translation.isNotEmpty) ...[
                Text(
                  '  ·  ',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
                TranslationCredit(
                  translationId: devotional.translation,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ReaderFooter extends ConsumerWidget {
  const _ReaderFooter({required this.devotional});

  final Devotional devotional;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: PrimaryButton(
          label: 'Start a walk with this',
          icon: Icons.directions_walk_rounded,
          expand: true,
          large: true,
          onPressed: () {
            ref
                .read(recordingControllerProvider.notifier)
                .carryDevotional(
                  devotional.title,
                  // Carried so scripture on the trail can prefer verses from
                  // the same collection this walk was started from.
                  category: devotional.category,
                );
            context.goNamed(Routes.record);
          },
        ),
      ),
    );
  }
}
