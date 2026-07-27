import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/widgets.dart';
import '../data/auth_repository.dart';
import 'widgets/brand_trail_mark.dart';

/// Log tag for the auth screen's own handling, distinct from the repository's
/// `[GoogleAuth]` stage log.
const _tag = 'AuthScreen';

enum _AuthMode {
  signIn('Sign in', 'Sign in', 'New here?', 'Create an account'),
  signUp('Create account', 'Create account', 'Already walking?', 'Sign in');

  const _AuthMode(this.tabLabel, this.submitLabel, this.switchPrompt, this.switchAction);

  final String tabLabel;
  final String submitLabel;
  final String switchPrompt;
  final String switchAction;
}

/// Sign in or create an account.
///
/// Talks to [AuthRepository] — real Supabase email/password and native Google.
/// On success the router's redirect takes over; failures show inline in the
/// app's voice, and a deliberately-dismissed Google sheet shows nothing at all.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscure = true;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
      // On success the router's redirect takes over; nothing to do here.
    } on AuthCancelled {
      // The person dismissed the Google sheet. Not a failure — say nothing and
      // just release the button.
      AppLogger.info(_tag, 'Cancelled by the person; releasing the button.');
    } on AuthFailure catch (error, stack) {
      AppLogger.warn(
        _tag,
        'AuthFailure code=${error.code ?? 'none'}: ${error.message}',
        error,
        error.stackTrace ?? stack,
      );
      if (!mounted) return;
      setState(() => _failure = error.message);
      // A failure carrying a code is a diagnosable one — put it on screen in
      // full, with its code and a way to copy it, so the emulator alone is
      // enough to work out what went wrong. Plain email failures ("wrong
      // password") stay as the inline notice.
      if (error.code != null) {
        await _report(
          ErrorReport(
            tag: _tag,
            title: 'Sign-in failed',
            code: error.code!,
            message: error.message,
            details: error.details,
            stackTrace: error.stackTrace ?? stack,
          ),
        );
      }
    } catch (error, stack) {
      // Never silent, and never a guess: the shared mapper decides what this
      // was. Only a real transport failure gets to mention the connection.
      final info = describeFailure(
        error,
        fallback: "That didn't go through.",
      );
      AppLogger.error(_tag, '${info.code} — ${info.diagnostic}', error, stack);
      if (!mounted) return;
      setState(() => _failure = info.message);
      await _report(
        info.toReport(
          tag: _tag,
          title: 'Sign-in failed',
          stackTrace: stack,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(ErrorReport report) async {
    if (!mounted) return;
    await showErrorReport(context, report);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = ref.read(authRepositoryProvider);
    _run(
      () => _mode == _AuthMode.signIn
          ? auth.signInWithEmail(
              email: _email.text,
              password: _password.text,
            )
          : auth.signUpWithEmail(
              email: _email.text,
              password: _password.text,
              fullName: _name.text,
            ),
    );
  }

  void _switchMode() {
    setState(() {
      _mode = _mode == _AuthMode.signIn ? _AuthMode.signUp : _AuthMode.signIn;
      _failure = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignUp = _mode == _AuthMode.signUp;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xxxl,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandTrailMark(size: 132)),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      isSignUp ? 'Start your first walk' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      isSignUp
                          ? 'Make an account and record what you carry.'
                          : 'Pick up where your last walk finished.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    SegmentedButton<_AuthMode>(
                      segments: [
                        for (final mode in _AuthMode.values)
                          ButtonSegment(value: mode, label: Text(mode.tabLabel)),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _mode = selection.first;
                          _failure = null;
                        });
                      },
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    if (isSignUp) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'The name on your profile',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Enter the name you want on your profile.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Enter your email address.';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                          return 'That email address is missing something.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: (value) => (value ?? '').length < 6
                          ? 'Passwords are at least 6 characters.'
                          : null,
                    ),

                    if (_failure != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _FailureNotice(message: _failure!),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: _mode.submitLabel,
                      expand: true,
                      large: true,
                      busy: _busy,
                      onPressed: _submit,
                    ),
                    // Native Google is mobile-only this phase (v7 uses a
                    // different renderButton flow on web), so the button is
                    // hidden there rather than wired onto a flow it doesn't fit.
                    if (!kIsWeb) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const _OrDivider(),
                      const SizedBox(height: AppSpacing.lg),
                      _GoogleButton(
                        busy: _busy,
                        onPressed: () => _run(
                          ref.read(authRepositoryProvider).signInWithGoogle,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    // Wrap, not Row: at large text sizes the prompt and the
                    // action no longer fit on one line.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _mode.switchPrompt,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        AppTextButton(
                          label: _mode.switchAction,
                          onPressed: _switchMode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppRadius.control,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or', style: theme.textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Text(
                'G',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('Continue with Google'),
          ],
        ),
      ),
    );
  }
}
