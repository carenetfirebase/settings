import 'package:material_ui/material_ui.dart';

import '../../../data/errors.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/labels.dart';
import '../theme.dart';
import '../tokens.dart';
import 'actions.dart';

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
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? Space.l : Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 56 : 80,
            height: compact ? 56 : 80,
            decoration: BoxDecoration(color: p.surfaceSoft, shape: BoxShape.circle),
            child: Icon(icon, size: compact ? 26 : 34, color: context.colors.primary),
          ),
          const SizedBox(height: Space.m),
          Semantics(
            header: true,
            child: Text(title, textAlign: TextAlign.center, style: compact ? context.text.titleLarge : context.text.headlineSmall),
          ),
          const SizedBox(height: Space.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: p.muted)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: Space.l),
            PrimaryActionButton(label: actionLabel!, onPressed: onAction, expand: false),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: Space.xs),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.title, required this.message, this.onRetry, this.icon = Icons.cloud_off_outlined});

  /// Defaults to "Something went wrong" in the current language.
  final String? title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  /// Friendly text for common error types; never leaks stack traces.
  /// Network failures: inventory changes are transactional and are never
  /// half-applied or silently queued, so the user is told to retry.
  static bool isOffline(Object error) {
    final s = error.toString();
    return s.contains('SocketException') || s.contains('network') || s.contains('unavailable') || s.contains('offline');
  }

  /// English text for [error]. Prefer [describeIn], which follows the
  /// app's language.
  static String describe(Object error) => describeWith(lookupAppLocalizations(const Locale('en', 'CA')), error);

  /// Friendly text for [error] in the current language.
  static String describeIn(BuildContext context, Object error) => describeWith(context.l10n, error);

  /// Friendly text for [error] in [l]'s language. Errors from the data layer
  /// carry an [AppErrorCode] and are translated; other short messages are
  /// shown as-is in English and replaced by a generic line elsewhere.
  static String describeWith(AppLocalizations l, Object error) {
    if (error is CodedError) {
      final code = error.code;
      if (code != null) return localizedError(l, code, error.args);
    }
    final s = error.toString();
    if (isOffline(error)) return l.coreErrorOffline;
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) return l.coreErrorPermissionDenied;
    if (_isEnglish(l) && s.length < 140 && !s.contains('Exception:') && !s.contains('Error:')) return s;
    return l.coreErrorGeneric;
  }

  static bool _isEnglish(AppLocalizations l) => l.localeName.startsWith('en');

  /// Translated text for a coded data-layer error.
  static String localizedError(AppLocalizations l, AppErrorCode code, Map<String, Object?> args) {
    String str(String k) => args[k]?.toString() ?? '';
    int number(String k) => (args[k] as num?)?.toInt() ?? 0;
    // Server/provider detail is English; show it only in English.
    String? detail() => _isEnglish(l) ? args['detail'] as String? : null;
    String label(String k) => args[k] == null ? '' : localizedLabel(l, args[k]!);
    return switch (code) {
      AppErrorCode.inventoryPlaceNameLength => l.coreErrPlaceNameLength,
      AppErrorCode.inventoryPlaceNameTaken => l.coreErrPlaceNameTaken(str('name')),
      AppErrorCode.inventoryPlaceLimit => l.coreErrPlaceLimit,
      AppErrorCode.inventoryBuiltInRename => l.coreErrBuiltInRename,
      AppErrorCode.inventoryBuiltInRemove => l.coreErrBuiltInRemove,
      AppErrorCode.inventoryPlaceNotEmpty => l.coreErrPlaceNotEmpty,
      AppErrorCode.inventoryNothingToAdd => l.coreErrNothingToAdd,
      AppErrorCode.inventoryQuantityNotPositive => l.coreErrQuantityNotPositive(str('product')),
      AppErrorCode.inventoryNothingToDeduct => l.coreErrNothingToDeduct,
      AppErrorCode.inventoryNothingToCorrect => l.coreErrNothingToCorrect,
      AppErrorCode.inventoryNegativeCount => l.coreErrNegativeCount,
      AppErrorCode.inventoryItemGone => l.coreErrItemGone,
      AppErrorCode.inventoryWrongUnit => l.coreErrWrongUnit(str('product'), label('unit')),
      AppErrorCode.inventoryNothingToUndo => l.coreErrNothingToUndo,
      AppErrorCode.inventoryAlreadyUndone => l.coreErrAlreadyUndone,
      AppErrorCode.inventoryUndoOfUndo => l.coreErrUndoOfUndo,
      AppErrorCode.inventoryProductNotRecorded => l.coreErrProductNotRecorded(str('product')),
      AppErrorCode.receiptNotFound => l.coreErrReceiptNotFound,
      AppErrorCode.receiptNotEditable => l.coreErrReceiptNotEditable,
      AppErrorCode.receiptNotReady => l.coreErrReceiptNotReady,
      AppErrorCode.receiptLinesIncomplete => l.coreErrReceiptLinesIncomplete(number('count')),
      AppErrorCode.receiptNoFoodItems => l.coreErrReceiptNoFoodItems,
      AppErrorCode.receiptNoPhotos => l.coreErrReceiptNoPhotos,
      AppErrorCode.receiptTooManyPages => l.coreErrReceiptTooManyPages(number('max')),
      AppErrorCode.receiptImageEmpty => l.coreErrImageEmpty,
      AppErrorCode.receiptImageTooLarge => l.coreErrImageTooLarge,
      AppErrorCode.receiptImageFormat => l.coreErrImageFormat,
      AppErrorCode.receiptDuplicate => l.coreErrReceiptDuplicate,
      AppErrorCode.aiUnavailable => detail() ?? l.coreErrAiUnavailable,
      AppErrorCode.notSignedIn => l.coreErrNotSignedIn,
      AppErrorCode.authCredentialMismatch => l.coreErrAuthCredentialMismatch,
      AppErrorCode.authEmailInUse => l.coreErrAuthEmailInUse,
      AppErrorCode.authWeakPassword => l.coreErrAuthWeakPassword,
      AppErrorCode.authInvalidEmail => l.coreErrAuthInvalidEmail,
      AppErrorCode.authOffline => l.coreErrAuthOffline,
      AppErrorCode.authTooManyRequests => l.coreErrAuthTooManyRequests,
      AppErrorCode.authRecentLoginRequired => l.coreErrAuthRecentLogin,
      AppErrorCode.authCancelled => l.coreErrAuthCancelled,
      AppErrorCode.authFailed => detail() ?? l.coreErrAuthFailed,
      AppErrorCode.authFailedRetry => l.coreErrAuthFailedRetry,
      AppErrorCode.authNoGoogleToken => l.coreErrAuthNoGoogleToken,
      AppErrorCode.authSignInAgain => l.coreErrAuthSignInAgain,
      AppErrorCode.authPasswordRequired => l.coreErrAuthPasswordRequired,
      AppErrorCode.authAppleNeedsFirebase => l.coreErrAuthAppleNeedsFirebase,
      AppErrorCode.authGoogleNeedsFirebase => l.coreErrAuthGoogleNeedsFirebase,
      AppErrorCode.householdOwnerNotRemovable => l.coreErrOwnerNotRemovable,
      AppErrorCode.sharingProfessionalNotVerified => l.coreErrProfessionalNotVerified,
      AppErrorCode.sharingNoCategories => l.coreErrNoShareCategories,
      AppErrorCode.sharingNoActivePermission => l.coreErrNoActivePermission(label('category')),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: EmptyState(
        icon: icon,
        title: title ?? context.l10n.coreErrorTitle,
        message: message,
        actionLabel: onRetry == null ? null : context.l10n.commonTryAgain,
        onAction: onRetry,
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message ?? context.l10n.commonLoading,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.4)),
            if (message != null) ...[
              const SizedBox(height: Space.m),
              ExcludeSemantics(child: Text(message!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when the OS denied a permission (camera, notifications…).
class PermissionDeniedState extends StatelessWidget {
  const PermissionDeniedState({super.key, required this.permission, required this.why, this.onOpenSettings, this.onAlternative, this.alternativeLabel});

  final String permission;
  final String why;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onAlternative;
  final String? alternativeLabel;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.lock_outline,
        title: context.l10n.corePermissionOff(permission),
        message: why,
        actionLabel: onOpenSettings == null ? null : context.l10n.coreOpenSettings,
        onAction: onOpenSettings,
        secondaryLabel: alternativeLabel,
        onSecondary: onAlternative,
      );
}

/// Convenience for rendering a Riverpod-style async value consistently.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.loadingMessage, this.onRetry});

  final ({T? data, Object? error, bool loading}) value;
  final Widget Function(T data) data;
  final String? loadingMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.error != null && value.data == null) {
      return ErrorState(message: ErrorState.describeIn(context, value.error!), onRetry: onRetry);
    }
    if (value.data == null) return LoadingState(message: loadingMessage);
    return data(value.data as T);
  }
}
