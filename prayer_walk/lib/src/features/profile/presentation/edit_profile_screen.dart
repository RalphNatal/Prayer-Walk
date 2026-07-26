import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../feed/data/mock_feed_repository.dart';
import '../data/mock_profile_repository.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  final _parish = TextEditingController();

  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _parish.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
        userId,
        ProfileEdit(
          displayName: _name.text,
          handle: _handle.text,
          bio: _bio.text,
          parish: _parish.text,
        ),
      );
      ref
        ..invalidate(currentProfileProvider)
        ..invalidate(profileProvider(userId))
        ..invalidate(feedProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Profile updated.');
      context.pop();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          "That didn't save. Check your connection, then try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: AsyncView<UserProfile>(
        value: profile,
        onRetry: () => ref.invalidate(currentProfileProvider),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: ShimmerScope(
            child: Column(
              children: [
                SkeletonBox(height: 56),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 56),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(height: 120),
              ],
            ),
          ),
        ),
        data: (item) {
          if (!_seeded) {
            _seeded = true;
            _name.text = item.displayName;
            _handle.text = item.handle;
            _bio.text = item.bio;
            _parish.text = item.parish;
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Center(
                  child: UserAvatar(
                    initials: item.initials,
                    accentIndex: item.accentIndex,
                    size: AppSizes.avatarLg,
                    ring: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Text(
                    'Photo uploads arrive with accounts in the next phase.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Your profile needs a name.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _handle,
                  decoration: const InputDecoration(
                    labelText: 'Handle',
                    prefixText: '@',
                    helperText: 'How people find you.',
                  ),
                  validator: (value) {
                    final text = (value ?? '').replaceAll('@', '').trim();
                    if (text.isEmpty) return 'Pick a handle.';
                    if (text.length < 3) {
                      return 'Handles are at least 3 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _parish,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Parish or community',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _bio,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 160,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'About you',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                PrimaryButton(
                  label: 'Save changes',
                  expand: true,
                  large: true,
                  busy: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
