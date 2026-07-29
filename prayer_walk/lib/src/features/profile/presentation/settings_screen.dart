import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../privacy/data/privacy_providers.dart';
import '../../privacy/domain/activity_visibility.dart';
import '../../scripture/presentation/scripture_credits.dart';
import '../../scripture/presentation/scripture_settings_panel.dart';

/// Appearance, notifications, and the way out.
///
/// The notification switches are local state only this phase — there is no
/// backend to store a preference against, and no push service to register
/// with. They are here so the shape of the screen is settled.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Seeded from the stored preference, which `main` has already read. Unlike
  /// the notification switches below, this one is real and persists.
  bool _haptics = AppHaptics.enabled;

  bool _encouragements = true;
  bool _comments = true;
  bool _newDevotionals = true;
  bool _weeklySummary = false;

  Future<void> _signOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: "You'll need to sign in again to get back in.",
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await ref.read(authRepositoryProvider).signOut();
    // The router redirect takes it from here.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.listBody,
        children: [
          const SectionHeader(
            title: 'Appearance',
            subtitle: 'Dark carries the trail well at night.',
          ),
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

          // Directly under Appearance and above everything else, because it is
          // the section with a consequence outside the phone. A privacy control
          // nobody scrolls to protects nobody.
          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Safety and privacy',
            subtitle:
                'Who sees your walks, where your routes are trimmed, and who '
                'is blocked.',
          ),
          Consumer(
            builder: (context, ref, _) {
              final visibility = ref.watch(defaultVisibilityProvider).value;
              final zones = ref.watch(privacyZonesProvider).value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: Text('Safety', style: theme.textTheme.titleSmall),
                subtitle: Text(
                  'New walks: '
                  '${(visibility ?? ActivityVisibility.standard).label.toLowerCase()}'
                  '${zones == null ? '' : '  ·  ${zones.isEmpty ? 'no privacy zones' : '${zones.length} privacy zone${zones.length == 1 ? '' : 's'}'}'}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.pushNamed(Routes.safety),
              );
            },
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Scripture on the trail',
            subtitle: 'The standing default. Each walk can be set differently '
                'from the record screen.',
          ),
          const ScriptureSettingsPanel(showHeader: false),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Touch',
            subtitle: 'A small response when something happens, for the walks '
                'where the phone stays in a pocket.',
          ),
          _SettingSwitch(
            title: 'Haptic feedback',
            subtitle: 'Start and finish, waypoints, encouragement, and when '
                'something fails to save.',
            value: _haptics,
            onChanged: (v) {
              setState(() => _haptics = v);
              AppHaptics.setEnabled(v);
            },
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Notifications',
            subtitle: 'Preview build — these are not wired to anything yet.',
          ),
          _SettingSwitch(
            title: 'Encouragement',
            subtitle: 'When someone responds to a walk.',
            value: _encouragements,
            onChanged: (v) => setState(() => _encouragements = v),
          ),
          _SettingSwitch(
            title: 'Comments',
            subtitle: 'When someone writes on a walk of yours.',
            value: _comments,
            onChanged: (v) => setState(() => _comments = v),
          ),
          _SettingSwitch(
            title: 'New devotionals',
            subtitle: 'When your parish publishes something.',
            value: _newDevotionals,
            onChanged: (v) => setState(() => _newDevotionals = v),
          ),
          _SettingSwitch(
            title: 'Weekly summary',
            subtitle: 'A note on Sunday with the week behind you.',
            value: _weeklySummary,
            onChanged: (v) => setState(() => _weeklySummary = v),
          ),

          // Below the scripture settings, above everything administrative: the
          // credits belong next to the feature they are a condition of, not on
          // a page nobody opens.
          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Contribute',
            subtitle:
                'A verse or a prayer that carried you through something is '
                'worth passing on.',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(
              'Suggest a scripture prompt',
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              'A moderator reads every suggestion before it goes on a walk.',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.pushNamed(Routes.submitScripture),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const ScriptureCreditsSection(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text('Open-source licences', style: theme.textTheme.titleSmall),
            subtitle: Text(
              'Fonts, packages, and the scripture notices above.',
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Prayer Walk',
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(title: 'Account'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
            title: Text(
              'Sign out',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            onTap: _signOut,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Prayer Walk · preview build',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      value: value,
      onChanged: onChanged,
    );
  }
}
