import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/data/avatar_image.dart';
import '../../profile/data/avatar_picker.dart';
import '../../profile/data/profile_providers.dart' show avatarPickerProvider;
import '../data/church_group_providers.dart';
import '../domain/church_group.dart';
import '../domain/church_group_fields.dart';
import 'widgets/church_group_tile.dart';
import 'widgets/group_avatar.dart';

const _tag = 'PW-GROUPS';

/// Starting a group, or editing one you look after.
///
/// One screen for both, as the admin content form is: the fields are the same
/// and a second copy is how the two would drift. Editing adds the pictures and
/// the way to close the group, which a group that does not exist yet has no
/// use for.
class ChurchGroupFormScreen extends ConsumerStatefulWidget {
  const ChurchGroupFormScreen({super.key, this.groupId});

  /// Null to start a new group.
  final String? groupId;

  @override
  ConsumerState<ChurchGroupFormScreen> createState() =>
      _ChurchGroupFormScreenState();
}

class _ChurchGroupFormScreenState extends ConsumerState<ChurchGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _about = TextEditingController();

  bool _discoverable = true;
  GroupJoinPolicy _policy = GroupJoinPolicy.open;
  bool _saving = false;
  bool _uploading = false;
  bool _filled = false;

  bool get _isEdit => widget.groupId != null;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _about.dispose();
    super.dispose();
  }

  /// Copies the loaded group into the fields once, the first time it arrives —
  /// never again, so a refresh does not overwrite what is being typed.
  void _fill(ChurchGroup group) {
    if (_filled) return;
    _filled = true;
    _name.text = group.name;
    _city.text = group.city;
    _about.text = group.description;
    _discoverable = group.isDiscoverable;
    _policy = group.joinPolicy;
  }

  ChurchGroupDraft get _draft => ChurchGroupDraft(
    name: _name.text,
    city: _city.text,
    description: _about.text,
    isDiscoverable: _discoverable,
    joinPolicy: _policy,
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final actions = ref.read(churchGroupActionsProvider);
    try {
      if (_isEdit) {
        await actions.update(widget.groupId!, _draft);
        if (!mounted) return;
        showAppSnackBar(context, 'Saved.');
        context.pop();
      } else {
        final group = await actions.create(_draft);
        if (!mounted) return;
        showAppSnackBar(
          context,
          "${group.name} is ready. You're its admin — invite your people.",
        );
        context.pushReplacementNamed(
          Routes.churchGroup,
          pathParameters: {'groupId': group.id},
        );
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: _isEdit
              ? "Your changes weren't saved. They're still here."
              : "The group wasn't created. Your details are still here.",
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage({required bool cover}) async {
    final groupId = widget.groupId;
    if (groupId == null) return;
    final picker = ref.read(avatarPickerProvider);
    try {
      final raw = await picker.pick(AvatarSource.gallery);
      if (raw == null || !mounted) return;
      setState(() => _uploading = true);
      final repo = ref.read(churchGroupRepositoryProvider);
      // Cropped, resized and stripped of every EXIF tag — GPS included —
      // before a byte leaves the device. A photo of a church taken from its
      // doorstep carries the doorstep.
      if (cover) {
        final prepared = await prepareCover(raw);
        AppLogger.info(
          _tag,
          'cover prepared: ${prepared.sizeBytes ~/ 1024} KB',
        );
        await repo.uploadCover(groupId, prepared);
      } else {
        final prepared = await prepareAvatar(raw);
        await repo.uploadAvatar(groupId, prepared);
      }
      ref
        ..invalidate(churchGroupProvider(groupId))
        ..invalidate(myGroupsProvider);
      if (mounted) {
        showAppSnackBar(context, cover ? 'Cover updated.' : 'Picture updated.');
      }
    } on AvatarImageFailure catch (failure, stack) {
      AppLogger.warn(
        _tag,
        'group image pick: ${failure.message}',
        failure,
        stack,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          failure.message,
          actionLabel: failure.canOpenSettings ? 'Settings' : null,
          onAction: failure.canOpenSettings ? picker.openSettings : null,
        );
      }
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "That picture didn't upload.",
          onRetry: () => _pickImage(cover: cover),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(ChurchGroup group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close ${group.name}?',
      message:
          'The group, its members list and every verse it shared are removed '
          "for everyone, and its scripture stops arriving on members' walks. "
          "This can't be undone.",
      confirmLabel: 'Close group',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(churchGroupActionsProvider).delete(group.id);
      if (!mounted) return;
      showAppSnackBar(context, '${group.name} was closed.');
      context.goNamed(
        Routes.discover,
        queryParameters: {Routes.discoverTabParam: Routes.discoverChurchesTab},
      );
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "The group wasn't closed.",
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEdit) return _scaffold(null);

    final group = ref.watch(churchGroupProvider(widget.groupId!));
    return AsyncView<ChurchGroup>(
      value: group,
      errorFallback: "This group couldn't be loaded.",
      onRetry: () => ref.invalidate(churchGroupProvider(widget.groupId!)),
      loading: Scaffold(
        appBar: AppBar(title: const Text('Edit group')),
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: RowListLoading(count: 4),
        ),
      ),
      data: (loaded) {
        _fill(loaded);
        return _scaffold(loaded);
      },
    );
  }

  Widget _scaffold(ChurchGroup? group) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit group' : 'Start a group')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.listBody,
          children: [
            if (group == null) ...[
              Text(
                "A group is your church's home on Prayer Walk. Members can "
                'find one another, and what you share reaches them on their '
                "walks. You'll be its first admin.",
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
            ] else ...[
              _Pictures(
                group: group,
                busy: _uploading,
                onAvatar: () => _pickImage(cover: false),
                onCover: () => _pickImage(cover: true),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],

            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: GroupLimits.nameMax,
              decoration: const InputDecoration(
                labelText: 'Church name',
                hintText: 'St Anne, Antipolo',
                counterText: '',
              ),
              validator: (value) => groupNameError(value ?? ''),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              maxLength: GroupLimits.city,
              decoration: const InputDecoration(
                labelText: 'Town or city (optional)',
                hintText: 'Antipolo, Rizal',
                helperText:
                    'Helps people tell your church from others of the '
                    'same name.',
                helperMaxLines: 2,
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _about,
              minLines: 3,
              maxLines: 8,
              maxLength: GroupLimits.description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'About (optional)',
                hintText: 'When you walk, where you meet, who is welcome.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            const SectionHeader(
              title: 'Who can join',
              subtitle: 'You can change this later.',
            ),
            RadioGroup<GroupJoinPolicy>(
              groupValue: _policy,
              onChanged: (value) => setState(() => _policy = value ?? _policy),
              child: Column(
                children: [
                  for (final policy in GroupJoinPolicy.values)
                    RadioListTile<GroupJoinPolicy>(
                      contentPadding: EdgeInsets.zero,
                      value: policy,
                      title: Text(policy.label),
                      subtitle: Text(
                        policy == GroupJoinPolicy.open
                            ? 'Members join straight away.'
                            : 'People ask, and an admin lets them in.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Listed in Discover',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                _discoverable
                    ? 'Anyone can find this group by name or town.'
                    : 'Hidden. People join only with the invite code you '
                          'share.',
                style: theme.textTheme.bodySmall,
              ),
              value: _discoverable,
              onChanged: (value) => setState(() => _discoverable = value),
            ),
            const SizedBox(height: AppSpacing.xl),

            PrimaryButton(
              label: _isEdit ? 'Save changes' : 'Start group',
              expand: true,
              large: true,
              busy: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: AppTextButton(
                label: 'Cancel',
                onPressed: _saving ? null : () => context.pop(),
              ),
            ),
            if (group != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              AppTextButton(
                label: 'Close this group',
                icon: Icons.delete_outline_rounded,
                destructive: true,
                onPressed: _saving ? null : () => _delete(group),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The cover and the mark, as they will look, each with its own change button.
class _Pictures extends StatelessWidget {
  const _Pictures({
    required this.group,
    required this.busy,
    required this.onAvatar,
    required this.onCover,
  });

  final ChurchGroup group;
  final bool busy;
  final VoidCallback onAvatar;
  final VoidCallback onCover;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.control,
          child: ChurchGroupCover(group: group),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            ChurchGroupAvatar(group: group, outlined: false),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  SecondaryButton(
                    label: 'Picture',
                    icon: Icons.photo_outlined,
                    busy: busy,
                    onPressed: onAvatar,
                  ),
                  SecondaryButton(
                    label: 'Cover',
                    icon: Icons.panorama_outlined,
                    busy: busy,
                    onPressed: onCover,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${memberCountLabel(group.memberCount)} · Location data is removed '
          'from photos before they upload.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
