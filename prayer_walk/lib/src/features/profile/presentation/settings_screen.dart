import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_repository.dart';

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
