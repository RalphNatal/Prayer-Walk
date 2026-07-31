import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../data/avatar_image.dart';
import '../data/avatar_picker.dart';
import '../data/profile_providers.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/profile_fields.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

/// Log tag for this screen's failures.
const _tag = 'PW-EDITPROFILE';

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
  final _pronouns = TextEditingController();
  final _location = TextEditingController();
  final _links = TextEditingController();

  bool _seeded = false;
  bool _saving = false;

  /// The photo is uploading. Separate from [_saving] because the two are
  /// separate round trips with separate failure modes — and because Save has to
  /// be disabled during an upload without claiming the form is being saved.
  bool _uploadingPhoto = false;

  bool get _busy => _saving || _uploadingPhoto;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _parish.dispose();
    _pronouns.dispose();
    _location.dispose();
    _links.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- the photo ---

  /// Camera, gallery, or remove. The sheet is built from what is actually
  /// available: there is nothing to remove when there is no photo, and offering
  /// it anyway is a button that does nothing.
  Future<void> _showPhotoSheet(UserProfile profile) async {
    final choice = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
            ),
            if (profile.avatarUrl != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _PhotoAction.camera:
        await _pickAndUpload(AvatarSource.camera);
      case _PhotoAction.gallery:
        await _pickAndUpload(AvatarSource.gallery);
      case _PhotoAction.remove:
        await _removePhoto();
    }
  }

  Future<void> _pickAndUpload(AvatarSource source) async {
    final userId = ref.read(currentAuthUserIdProvider);
    if (userId == null) return;
    final picker = ref.read(avatarPickerProvider);

    try {
      final raw = await picker.pick(source);
      // Backed out of the camera or the picker. Not a failure, and not
      // something to say anything about.
      if (raw == null || !mounted) return;

      setState(() => _uploadingPhoto = true);

      // Resize, square-crop and — the part that matters — strip every EXIF
      // tag, GPS included, before a single byte leaves the device.
      final prepared = await prepareAvatar(raw);
      AppLogger.info(
        _tag,
        'avatar prepared: ${prepared.edge}px, ${prepared.sizeBytes ~/ 1024} KB',
      );

      await ref.read(profileRepositoryProvider).uploadAvatar(userId, prepared);
      _refreshProfileEverywhere(userId);

      if (mounted) showAppSnackBar(context, 'Photo updated.');
    } on AvatarImageFailure catch (failure, stack) {
      // A refused permission or a file we cannot read. Already phrased; logged
      // anyway, because a phrased failure is still one that happened.
      AppLogger.warn(_tag, 'avatar pick: ${failure.message}', failure, stack);
      if (mounted) _showPermissionFailure(failure, picker);
    } catch (error, stack) {
      // The upload itself. The previous photo is untouched — the repository
      // only re-points the row once the new object is written — so there is
      // nothing to roll back and nothing on screen has changed.
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "Your photo didn't upload.",
          onRetry: () => _pickAndUpload(source),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// A denied permission is the one failure with somewhere to go, so it gets an
  /// action instead of a Retry that would only be refused again.
  void _showPermissionFailure(AvatarImageFailure failure, AvatarPicker picker) {
    showAppSnackBar(
      context,
      failure.message,
      actionLabel: failure.canOpenSettings ? 'Settings' : null,
      onAction: failure.canOpenSettings ? picker.openSettings : null,
    );
  }

  Future<void> _removePhoto() async {
    final userId = ref.read(currentAuthUserIdProvider);
    if (userId == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      await ref.read(profileRepositoryProvider).removeAvatar(userId);
      _refreshProfileEverywhere(userId);
      if (mounted) showAppSnackBar(context, 'Photo removed.');
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "Your photo wasn't removed.",
          onRetry: _removePhoto,
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // -------------------------------------------------------------- the form ---

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final userId = ref.read(currentAuthUserIdProvider);
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            userId,
            ProfileEdit(
              displayName: _name.text,
              handle: _handle.text,
              bio: _bio.text,
              parish: _parish.text,
              pronouns: _pronouns.text,
              location: _location.text,
              links: _links.text,
            ),
          );
      _refreshProfileEverywhere(userId);
      if (!mounted) return;
      showAppSnackBar(context, 'Profile updated.');
      context.pop();
    } on ProfileFailure catch (failure, stack) {
      // Already phrased for the person — a taken handle, most often. Logged
      // anyway: a phrased failure is still one that happened.
      AppLogger.warn(_tag, 'ProfileFailure: ${failure.message}', failure, stack);
      if (mounted) showAppSnackBar(context, failure.message);
    } catch (error, stack) {
      if (mounted) {
        reportFailure(
          context,
          error,
          stack,
          tag: _tag,
          fallback: "Your profile didn't save.",
          // The one unique index on this table is the handle, so a 23505 here
          // means exactly one thing.
          uniqueMessage: "That handle's taken — try another.",
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Both caches that can be holding this person.
  ///
  /// `currentProfileProvider` is the one this screen watches;
  /// `profileProvider(id)` is what the feed byline, a comment author and a
  /// discovery row resolve through. Invalidating only the first leaves a new
  /// photo showing on the profile and the old one everywhere else until the app
  /// is restarted, which is exactly the bug this line exists to prevent.
  void _refreshProfileEverywhere(String userId) {
    ref.invalidate(currentProfileProvider);
    ref.invalidate(profileProvider(userId));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: AsyncView<UserProfile>(
        value: profile,
        errorFallback: "Your profile couldn't be loaded for editing.",
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
            // Stored with the leading '@'; the field draws its own prefix.
            _handle.text = item.handle.replaceFirst('@', '');
            _bio.text = item.bio;
            _parish.text = item.parish;
            _pronouns.text = item.pronouns;
            _location.text = item.location;
            _links.text = item.links;
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _PhotoField(
                  profile: item,
                  uploading: _uploadingPhoto,
                  onTap: _busy ? null : () => _showPhotoSheet(item),
                ),
                const SizedBox(height: AppSpacing.xl),

                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: ProfileLimits.displayName,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    // Suppresses the counter without losing the cap — a hard
                    // stop on a field nobody is near is just clutter.
                    counterText: '',
                  ),
                  validator: (value) => displayNameError(value ?? ''),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _handle,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Handle',
                    prefixText: '@',
                    helperText: 'How people find you. Letters, numbers, . - _',
                  ),
                  validator: (value) => handleError(value ?? ''),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _pronouns,
                  maxLength: ProfileLimits.pronouns,
                  decoration: const InputDecoration(
                    labelText: 'Pronouns (optional)',
                    hintText: 'she/her, they/them',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _parish,
                  textCapitalization: TextCapitalization.words,
                  maxLength: ProfileLimits.parish,
                  decoration: const InputDecoration(
                    labelText: 'Parish or community',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _location,
                  textCapitalization: TextCapitalization.words,
                  maxLength: ProfileLimits.location,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    hintText: 'Antipolo, Rizal',
                    // Said plainly, because the word "location" in a walking
                    // app could reasonably be read as something the phone
                    // measures. It is a city, typed by hand, and nothing here
                    // reads a position.
                    helperText: 'A city or area you type yourself — not your '
                        'GPS position.',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _links,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  maxLength: ProfileLimits.links,
                  decoration: const InputDecoration(
                    labelText: 'Link (optional)',
                    hintText: 'prayerwalk.org',
                    helperText: 'A personal or parish page.',
                    counterText: '',
                  ),
                  validator: (value) => linkError(value ?? ''),
                ),
                const SizedBox(height: AppSpacing.lg),

                TextFormField(
                  controller: _bio,
                  minLines: 3,
                  maxLines: 5,
                  // The one field with a visible counter: it is the only one
                  // somebody writes their way up against.
                  maxLength: ProfileLimits.bio,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'About you',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Every field on this screen is visible to every signed-in
                // member — `profiles` is readable app-wide, which is what the
                // feed byline and discovery are built on. Better said once,
                // here, than assumed otherwise by someone typing their address
                // into Location.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Everything on this page is visible to other members.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                PrimaryButton(
                  label: 'Save changes',
                  expand: true,
                  large: true,
                  busy: _saving,
                  // Disabled during a photo upload too: saving mid-upload would
                  // race a second write against the row the upload is about to
                  // re-point.
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _PhotoAction { camera, gallery, remove }

/// The avatar, and the one control that changes it.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.profile,
    required this.uploading,
    required this.onTap,
  });

  final UserProfile profile;
  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Semantics(
          button: true,
          label: profile.avatarUrl == null
              ? 'Add a profile photo'
              : 'Change your profile photo',
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                UserAvatar(
                  initials: profile.initials,
                  accentIndex: profile.accentIndex,
                  imageUrl: profile.avatarUrl,
                  size: AppSizes.avatarLg,
                  ring: true,
                ),
                // Over the avatar rather than beside it: the thing being waited
                // for is the picture, so that is where the spinner belongs.
                if (uploading)
                  Container(
                    width: AppSizes.avatarLg,
                    height: AppSizes.avatarLg,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                    ),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: onTap,
          child: Text(
            uploading
                ? 'Uploading…'
                : profile.avatarUrl == null
                ? 'Add photo'
                : 'Change photo',
          ),
        ),
      ],
    );
  }
}
