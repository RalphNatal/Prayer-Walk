import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../data/auth_providers.dart';
import 'widgets/brand_trail_mark.dart';

/// Three screens on what the app is for, then out of the way.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <({String title, String body})>[
    (
      title: 'Walk it, and mean it',
      body:
          'Record a walk, run, hike or ride the way you already do — and carry '
          'something with you while you move.',
    ),
    (
      title: 'Mark the places you prayed',
      body:
          'Drop a waypoint where you stopped. They sit on your route as small '
          'lights, so the walk remembers what you brought to it.',
    ),
    (
      title: 'Walk it with other people',
      body:
          'Follow your parish, send encouragement, and read devotionals written '
          'for the streets you are actually on.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    // Marks onboarding seen for this run; the redirect moves on to sign-in.
    ref.read(onboardingSeenProvider.notifier).markSeen();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    if (context.reduceMotion) {
      _controller.jumpToPage(_page + 1);
    } else {
      _controller.nextPage(
        duration: AppDurations.medium,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: AppTextButton(label: 'Skip', onPressed: _finish),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BrandTrailMark(size: 220, animate: index == 0),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Semantics(
                    label: 'Page ${_page + 1} of ${_pages.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: context.reduceMotion
                                ? Duration.zero
                                : AppDurations.fast,
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            height: 6,
                            width: i == _page ? 24 : 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: AppRadius.chip,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: isLast ? 'Get started' : 'Next',
                    expand: true,
                    large: true,
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
