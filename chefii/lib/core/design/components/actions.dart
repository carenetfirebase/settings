import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/units/units.dart';
import '../theme.dart';
import '../tokens.dart';

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({super.key, required this.label, required this.onPressed, this.icon, this.loading = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: context.colors.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.xs)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final button = FilledButton(
      onPressed: loading ? null : onPressed == null ? null : () {
        HapticFeedback.selectionClick();
        onPressed!();
      },
      child: child,
    );
    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      label: loading ? '$label, in progress' : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({super.key, required this.label, required this.onPressed, this.icon, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: Space.xs)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// − value + with large targets, unit label and screen-reader adjustments.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step,
    this.min = 0,
    this.max,
    this.label,
  });

  final Quantity value;
  final ValueChanged<Quantity> onChanged;

  /// Defaults: 1 for pieces, 50 for g/ml, 0.25 for kg/L/cups.
  final double? step;
  final double min;
  final double? max;
  final String? label;

  double get _step {
    if (step != null) return step!;
    return switch (value.unit) {
      Unit.piece || Unit.dozen => 1,
      Unit.g || Unit.ml => value.amount >= 500 ? 100 : 25,
      Unit.mg => 100,
      Unit.tsp || Unit.tbsp => 0.5,
      _ => 0.25,
    };
  }

  void _set(double v) {
    var next = v < min ? min : v;
    if (max != null && next > max!) next = max!;
    HapticFeedback.selectionClick();
    onChanged(Quantity(double.parse(next.toStringAsFixed(3)), value.unit));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canDec = value.amount - _step >= min - 1e-9;
    final canInc = max == null || value.amount + _step <= max! + 1e-9;
    return Semantics(
      label: label,
      value: value.format(),
      increasedValue: Quantity(value.amount + _step, value.unit).format(),
      decreasedValue: Quantity((value.amount - _step).clamp(min, double.infinity), value.unit).format(),
      onIncrease: canInc ? () => _set(value.amount + _step) : null,
      onDecrease: canDec ? () => _set(value.amount - _step) : null,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: p.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: IconButton(
                tooltip: 'Less',
                onPressed: canDec ? () => _set(value.amount - _step) : null,
                icon: const Icon(Icons.remove),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: ExcludeSemantics(
                child: Text(value.format(), textAlign: TextAlign.center, style: context.text.titleMedium),
              ),
            ),
            ExcludeSemantics(
              child: IconButton(
                tooltip: 'More',
                onPressed: canInc ? () => _set(value.amount + _step) : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet confirmation for consequential actions.
/// Returns true only when the user explicitly confirms.
Future<bool> showConfirmActionSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Widget? extra,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ConfirmActionSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      extra: extra,
    ),
  );
  return result ?? false;
}

class ConfirmActionSheet extends StatelessWidget {
  const ConfirmActionSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.extra,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
            const SizedBox(height: Space.xs),
            Text(message, style: context.text.bodyMedium?.copyWith(color: p.muted)),
            if (extra != null) ...[const SizedBox(height: Space.m), extra!],
            const SizedBox(height: Space.l),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: destructive ? FilledButton.styleFrom(backgroundColor: p.error, foregroundColor: Colors.white) : null,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ),
            const SizedBox(height: Space.xs),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Undo-capable snackbar for inventory changes.
void showUndoSnack(BuildContext context, String message, {VoidCallback? onUndo}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 6),
    action: onUndo == null ? null : SnackBarAction(label: 'Undo', onPressed: onUndo),
  ));
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      if (error) ...[const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: Space.xs)],
      Expanded(child: Text(message)),
    ]),
  ));
}
