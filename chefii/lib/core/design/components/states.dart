import 'package:material_ui/material_ui.dart';

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
  const ErrorState({super.key, this.title = 'Something went wrong', required this.message, this.onRetry, this.icon = Icons.cloud_off_outlined});

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  /// Friendly text for common error types; never leaks stack traces.
  static String describe(Object error) {
    final s = error.toString();
    if (s.contains('SocketException') || s.contains('network') || s.contains('unavailable')) {
      return 'You appear to be offline. Your kitchen is saved on this device and will sync when you reconnect.';
    }
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'You don\'t have access to this. If it was shared with you, the owner may have changed permissions.';
    }
    if (s.length < 140 && !s.contains('Exception:') && !s.contains('Error:')) return s;
    return 'Please try again in a moment.';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: EmptyState(icon: icon, title: title, message: message, actionLabel: onRetry == null ? null : 'Try again', onAction: onRetry),
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
      label: message ?? 'Loading',
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
        title: '$permission is turned off',
        message: why,
        actionLabel: onOpenSettings == null ? null : 'Open Settings',
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
      return ErrorState(message: ErrorState.describe(value.error!), onRetry: onRetry);
    }
    if (value.data == null) return LoadingState(message: loadingMessage);
    return data(value.data as T);
  }
}
