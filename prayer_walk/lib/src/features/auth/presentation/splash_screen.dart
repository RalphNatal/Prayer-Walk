import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/brand_trail_mark.dart';

/// The brand moment, held while the session restores.
///
/// It does not navigate. The router's redirect moves on the moment the session
/// resolves, which means the splash lasts exactly as long as the work does —
/// no arbitrary timer to sit through.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pine,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A4A3A), AppColors.pine, Color(0xFF16281F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const BrandTrailMark(size: 200),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Prayer Walk',
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: AppColors.parchment,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Every step, an offering.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.parchment.withValues(alpha: 0.76),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 96,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: AppColors.parchment.withValues(alpha: 0.18),
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
