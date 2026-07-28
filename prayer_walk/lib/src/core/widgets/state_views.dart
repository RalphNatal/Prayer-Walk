import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../utils/app_exception.dart';
import '../utils/error_messages.dart';
import 'app_buttons.dart';
import 'error_report_dialog.dart';

/// An empty list, framed as an invitation rather than an absence.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextButton(label: secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

/// What happened, and what to do about it. No apology.
///
/// Two of the three states a list can be in that are not "here is your list".
/// The third is [EmptyState], and keeping them visibly apart is the whole job
/// of this widget:
///
/// * **failed** — a transport blip, an expired session, a policy refusal. The
///   person can retry and it might work. Cloud-off icon, retry, details.
/// * **not set up** — the table or RPC is not in the database, because a
///   migration has not been applied. Retrying will fail identically forever, so
///   there is no retry button; in debug the object and its migration file are
///   named on screen. See `AppErrorInfo.isSchemaMissing`.
/// * **empty** — [EmptyState], and nothing here. The shelf being bare is not a
///   failure and must never be dressed as one.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
    this.fallback = "That didn't load.",
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  /// What the person reads when the cause is not one the mapper recognises.
  ///
  /// Names *this* screen's action — "Devotionals couldn't be loaded." — rather
  /// than the generic line, so a failure says which thing failed. It is also
  /// the dialog's body, which is why the heading below is a separate, shorter
  /// string: one statement of the problem per surface.
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appError = error is AppException ? error as AppException : null;
    // What actually failed, rather than the old assumption that every failed
    // read was the network. An [AppException] still speaks for itself; a
    // Postgres code gets named; anything unrecognised gets the caller's line
    // and the details button below.
    final info = describeFailure(error, fallback: fallback);
    final notSetUp = info.isSchemaMissing;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              // Not a cloud with a line through it: nothing is disconnected.
              notSetUp ? Icons.dns_outlined : Icons.cloud_off_rounded,
              size: 28,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            info.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          // Only a developer can act on this, and only in a build where the
          // name means something. Kept out of release by [kDebugMode] as well
          // as by the mapper, which does not name objects on a shipped build.
          if (notSetUp && kDebugMode) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A migration has not been applied. '
              'Open Details, or check the [PW-SCHEMA] block in the log.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // No retry for a missing table. The button would be a promise that
          // pressing it changes something, and it cannot.
          if (onRetry != null && !notSetUp) ...[
            const SizedBox(height: AppSpacing.xl),
            SecondaryButton(
              label: appError?.actionLabel ?? 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
          // Only where the friendly line does not already name the cause —
          // a phrased [AppException] has nothing more to show.
          if (appError == null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextButton(
              label: 'Details',
              onPressed: () => showErrorReport(
                context,
                // A heading, not a second copy of the sentence already on
                // screen. `ErrorReport` enforces this too, but a caller that
                // relies on being corrected is a caller that says nothing.
                info.toReport(
                  tag: 'PW-LOAD',
                  title: notSetUp ? 'Not set up on the server' : 'Load failed',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
