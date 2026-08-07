import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_providers.dart';

/// Console settings. Deliberately sparse — most of what belongs here needs a
/// backend to configure against.
class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: "You'll need to sign in again to get back in.",
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeControllerProvider);
    final profile = ref.watch(currentProfileProvider);

    return AdminPage(
      title: 'Settings',
      subtitle: 'Admin console',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SectionHeader(title: 'Signed in as', dense: true),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.control,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                if (profile.value case final person?) ...[
                  UserAvatar(
                    initials: person.initials,
                    accentIndex: person.accentIndex,
                    imageUrl: person.avatarUrl,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '${person.handle}  ·  admin console',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Expanded(
                    child: ShimmerScope(child: ListRowSkeleton()),
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(title: 'Appearance', dense: true),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => ref
                .read(themeModeControllerProvider.notifier)
                .set(selection.first),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Console',
            subtitle: 'Not yet configurable — on the way.',
            dense: true,
          ),
          const _PlaceholderRow(
            icon: Icons.gavel_outlined,
            title: 'Moderation rules',
            subtitle: 'Auto-flag terms, report thresholds.',
          ),
          const _PlaceholderRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Parish directory',
            subtitle: 'Which communities members can join.',
          ),
          const _PlaceholderRow(
            icon: Icons.download_outlined,
            title: 'Data export',
            subtitle: 'Activity and membership reports.',
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(title: 'Account', dense: true),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
            title: Text(
              'Sign out',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            onTap: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: false,
      leading: Icon(icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Text('Soon', style: theme.textTheme.labelSmall),
    );
  }
}
