import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/data/mock_profile_repository.dart';
import '../data/mock_admin_repository.dart';
import '../domain/admin_models.dart';

/// Write a broadcast, see who it reaches, confirm before it goes.
class AdminAnnouncementComposeScreen extends ConsumerStatefulWidget {
  const AdminAnnouncementComposeScreen({super.key});

  @override
  ConsumerState<AdminAnnouncementComposeScreen> createState() =>
      _AdminAnnouncementComposeScreenState();
}

class _AdminAnnouncementComposeScreenState
    extends ConsumerState<AdminAnnouncementComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  AnnouncementAudience _audience = AnnouncementAudience.everyone;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final recipients = ref.read(audienceSizeProvider(_audience)).value ?? 0;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Send to ${_audience.label.toLowerCase()}?',
      message:
          'This goes out to ${Fmt.plural(recipients, 'person', 'people')} '
          'straight away. It cannot be recalled.',
      confirmLabel: 'Send',
    );
    if (!confirmed) return;

    setState(() => _sending = true);
    try {
      final sentByName =
          ref.read(currentProfileProvider).value?.displayName ?? 'Admin';
      await ref.read(adminRepositoryProvider).sendAnnouncement(
        title: _title.text,
        body: _body.text,
        audience: _audience,
        sentByName: sentByName,
      );
      ref.invalidate(announcementsProvider);
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Sent to ${Fmt.plural(recipients, 'person', 'people')}.',
      );
      context.pop();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          "That didn't send. Check your connection, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recipients = ref.watch(audienceSizeProvider(_audience));

    return AdminPage(
      title: 'Compose announcement',
      showBack: true,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the announcement a title.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _body,
              minLines: 5,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value == null || value.trim().length < 10)
                  ? 'Write the message members will read.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            Text('Audience', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<AnnouncementAudience>(
              groupValue: _audience,
              onChanged: (value) =>
                  setState(() => _audience = value ?? _audience),
              child: Column(
                children: [
                  for (final audience in AnnouncementAudience.values)
                    RadioListTile<AnnouncementAudience>(
                      contentPadding: EdgeInsets.zero,
                      value: audience,
                      title: Text(audience.label),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: AppRadius.control,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      switch (recipients) {
                        AsyncValue(hasValue: true, value: final count?) =>
                          'Reaches ${Fmt.plural(count, 'person', 'people')}.',
                        AsyncValue(hasError: true) =>
                          "Couldn't count the audience. The send will still work.",
                        _ => 'Counting the audience…',
                      },
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Send announcement',
              icon: Icons.send_rounded,
              expand: true,
              large: true,
              busy: _sending,
              onPressed: _send,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Text(
                'Preview build — nothing is actually delivered.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
