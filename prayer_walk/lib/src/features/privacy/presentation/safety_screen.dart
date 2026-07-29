import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../data/privacy_actions.dart';
import '../data/privacy_providers.dart';
import '../domain/activity_visibility.dart';
import '../domain/privacy_zone.dart';
import 'visibility_picker.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-SAFETY';

/// B4 · Safety, in one place.
///
/// Four things a member can do about who reaches them, gathered rather than
/// scattered: the audience new walks start with, the places their routes are
/// trimmed, the people they have shut out, and how to report something.
///
/// It is a section of Settings rather than a screen buried under an icon,
/// because the fact that any of this exists is most of its value. A privacy
/// control nobody can find protects nobody.
class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  Future<void> _setDefault(
    BuildContext context,
    WidgetRef ref,
    ActivityVisibility visibility,
  ) async {
    try {
      await ref.read(privacyActionsProvider).setDefaultVisibility(visibility);
    } catch (error, stack) {
      if (context.mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That setting didn't save.",
        );
      }
      return;
    }
    if (context.mounted) {
      showAppSnackBar(
        context,
        'New walks will be visible to ${visibility.label.toLowerCase()}.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final defaultVisibility = ref.watch(defaultVisibilityProvider);
    final zones = ref.watch(privacyZonesProvider);
    final blocked = ref.watch(blockedMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: AppSpacing.listBody,
        children: [
          const SectionHeader(
            title: 'Who sees new walks',
            subtitle:
                'The audience a walk starts with. Every walk can still be set '
                'differently when you save it.',
          ),
          VisibilityPicker(
            // Unresolved reads as the standing default rather than as a
            // spinner: this is a settings row, and the value it shows while
            // loading is the same one the server will confirm.
            value: defaultVisibility.value ?? ActivityVisibility.standard,
            onChanged: (chosen) => _setDefault(context, ref, chosen),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'Privacy zones',
            subtitle:
                'Places your routes are trimmed before anyone else sees them.',
          ),
          _SafetyRow(
            icon: Icons.shield_outlined,
            title: 'Privacy zones',
            subtitle: switch (zones) {
              AsyncData(:final value) when value.isEmpty =>
                'None set. Most walks start and finish at home.',
              AsyncData(:final value) =>
                '${value.length} zone${value.length == 1 ? '' : 's'} — routes '
                    'are trimmed at both ends.',
              AsyncError() => 'Open to check your zones.',
              _ => 'Loading…',
            },
            onTap: () => context.pushNamed(Routes.privacyZones),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              PrivacyZone.explainer,
              style: theme.textTheme.bodySmall,
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          const SectionHeader(
            title: 'People',
            subtitle:
                'Blocking is immediate and works both ways. Reporting asks a '
                'moderator to look at something that has already happened — '
                'you can do both.',
          ),
          _SafetyRow(
            icon: Icons.block_rounded,
            title: 'Blocked members',
            subtitle: switch (blocked) {
              AsyncData(:final value) when value.isEmpty => 'Nobody blocked.',
              AsyncData(:final value) =>
                '${value.length} blocked. They cannot see your walks, your '
                    'profile, or reach you at all.',
              AsyncError() => 'Open to check your list.',
              _ => 'Loading…',
            },
            onTap: () => context.pushNamed(Routes.blockedMembers),
          ),

          const SizedBox(height: AppSpacing.xl),
          const _SafetyExplainer(),
        ],
      ),
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// The whole of it, in four sentences, at the bottom where somebody looking for
/// reassurance will find it.
class _SafetyExplainer extends StatelessWidget {
  const _SafetyExplainer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How this works', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A walk is only readable by the audience you gave it — the server '
            'refuses everyone else, not just the app. Privacy zones are '
            'applied before a route is sent, so the trimmed part never reaches '
            'anyone else\'s phone. Nobody, including us, can see where your '
            'zones are. Reporting a walk or a comment sends it to a moderator; '
            'blocking takes effect immediately and does not wait for anybody.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
