import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/receipt.dart';
import '../../domain/units/units.dart';
import '../kitchen/kitchen_sheets.dart';
import '../shared/photo_picker.dart';

/// Pages captured but not yet submitted (screens 12–13).
class ReceiptDraft extends Notifier<List<ReceiptPage>> {
  @override
  List<ReceiptPage> build() => const [];

  void add(ReceiptPage p) => state = [...state, p];
  void replace(int i, ReceiptPage p) => state = [...state]..[i] = p;
  void removeAt(int i) => state = [...state]..removeAt(i);
  void clear() => state = const [];
}

final receiptDraftProvider = NotifierProvider<ReceiptDraft, List<ReceiptPage>>(ReceiptDraft.new);

// ---------------------------------------------------------------- 12 Capture

class ReceiptCaptureScreen extends ConsumerStatefulWidget {
  const ReceiptCaptureScreen({super.key});

  @override
  ConsumerState<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends ConsumerState<ReceiptCaptureScreen> {
  bool _busy = false;
  bool _denied = false;

  bool get _hasDocScanner => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  Future<void> _scanDocument() async {
    setState(() => _busy = true);
    try {
      final paths = await CunningDocumentScanner.getPictures(noOfPages: ReceiptImageRules.maxPages);
      if (paths == null || paths.isEmpty) return;
      for (final path in paths) {
        final bytes = await XFile(path).readAsBytes();
        ref.read(receiptDraftProvider.notifier).add(ReceiptPage(bytes, ReceiptImageRules.sniffMime(bytes) ?? 'image/jpeg'));
      }
      if (mounted) context.push('/receipt/preview');
    } on CunningDocumentScannerException {
      // Scanner unavailable or denied: fall back to the plain camera.
      await _photo(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(bool camera) async {
    setState(() {
      _busy = true;
      _denied = false;
    });
    try {
      final p = await pickPhoto(camera: camera);
      if (p == null) return;
      ref.read(receiptDraftProvider.notifier).add(p);
      if (mounted) context.push('/receipt/preview');
    } on PhotoPermissionDenied {
      setState(() => _denied = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = ref.watch(aiGatewayProvider).isDemo;
    return PremiumAppScaffold(
      header: const EditorialPageHeader(
        eyebrow: 'Receipt',
        title: 'Scan a receipt',
        subtitle: 'Lay it flat in good light. Long receipts can be captured in a few pages.',
      ),
      primaryAction: PrimaryActionButton(
        icon: Icons.document_scanner_outlined,
        label: _hasDocScanner ? 'Scan receipt' : 'Take a photo',
        loading: _busy,
        onPressed: _hasDocScanner ? _scanDocument : () => _photo(true),
      ),
      children: [
        if (isDemo) const DemoBanner(message: 'Demo mode: any photo works — we\'ll show a labelled sample receipt instead of reading it.'),
        if (_denied)
          PermissionDeniedState(
            permission: 'Camera',
            why: 'Allow camera access in Settings to scan receipts, or import a photo you already took.',
            alternativeLabel: 'Import a photo',
            onAlternative: () => _photo(false),
          ),
        const FoodArtwork(artKey: 'cream', height: 200, label: 'Receipt on a kitchen counter'),
        const SizedBox(height: Space.l),
        for (final (icon, text) in [
          (Icons.light_mode_outlined, 'Bright, even light — avoid shadows across the paper'),
          (Icons.crop_free, 'Include the store name at the top and the total at the bottom'),
          (Icons.layers_outlined, 'For long receipts, capture each section as its own page'),
          (Icons.lock_outline, 'Photos are stored privately for your household and used only to read your purchases'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: context.colors.primary),
              const SizedBox(width: Space.s),
              Expanded(child: Text(text, style: context.text.bodyMedium)),
            ]),
          ),
        const SizedBox(height: Space.s),
        if (_hasDocScanner) TextButton.icon(onPressed: _busy ? null : () => _photo(true), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Use the regular camera')),
        TextButton.icon(onPressed: _busy ? null : () => _photo(false), icon: const Icon(Icons.photo_library_outlined), label: const Text('Import from photos')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 13 Preview

class ReceiptPreviewScreen extends ConsumerStatefulWidget {
  const ReceiptPreviewScreen({super.key});

  @override
  ConsumerState<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends ConsumerState<ReceiptPreviewScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _rotate(int i) async {
    final page = ref.read(receiptDraftProvider)[i];
    setState(() => _busy = true);
    try {
      final rotated = await compute(_rotateJpeg, page.bytes);
      if (rotated != null) ref.read(receiptDraftProvider.notifier).replace(i, ReceiptPage(rotated, 'image/jpeg'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze({bool allowDuplicate = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(actionsProvider).submitReceipt(ref.read(receiptDraftProvider), allowDuplicate: allowDuplicate);
      ref.read(receiptDraftProvider.notifier).clear();
      if (mounted) context.pushReplacement('/receipt/$id/processing');
    } on DuplicateReceiptException catch (e) {
      if (mounted) context.push('/receipt/${e.existing.id}/error?reason=duplicate');
    } on ReceiptValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = ErrorState.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(receiptDraftProvider);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Receipt', title: 'Check your photo', subtitle: '${pages.length} page${pages.length == 1 ? '' : 's'}. Make sure the text is sharp.'),
      primaryAction: PrimaryActionButton(label: 'Analyze receipt', loading: _busy, onPressed: pages.isEmpty ? null : _analyze),
      children: [
        if (pages.isEmpty)
          EmptyState(icon: Icons.receipt_long_outlined, title: 'No pages yet', message: 'Capture your receipt to continue.', actionLabel: 'Capture', onAction: () => context.pop()),
        for (var i = 0; i < pages.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: Space.s),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Semantics(
                image: true,
                label: 'Receipt page ${i + 1}',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(pages[i].bytes, fit: BoxFit.contain, width: double.infinity, gaplessPlayback: true),
                ),
              ),
              Row(children: [
                const SizedBox(width: Space.m),
                Text('Page ${i + 1}', style: context.text.labelMedium),
                const Spacer(),
                IconButton(tooltip: 'Rotate', onPressed: _busy ? null : () => _rotate(i), icon: const Icon(Icons.rotate_right)),
                IconButton(
                  tooltip: 'Retake',
                  onPressed: _busy
                      ? null
                      : () async {
                          final p = await pickPhoto(camera: true);
                          if (p != null) ref.read(receiptDraftProvider.notifier).replace(i, p);
                        },
                  icon: const Icon(Icons.replay),
                ),
                IconButton(tooltip: 'Remove page', onPressed: _busy ? null : () => ref.read(receiptDraftProvider.notifier).removeAt(i), icon: const Icon(Icons.delete_outline)),
              ]),
            ]),
          ),
        if (pages.isNotEmpty && pages.length < ReceiptImageRules.maxPages)
          SecondaryActionButton(
            icon: Icons.add_photo_alternate_outlined,
            label: 'Add another page',
            onPressed: _busy
                ? null
                : () async {
                    final p = await pickPhoto(camera: true);
                    if (p != null) ref.read(receiptDraftProvider.notifier).add(p);
                  },
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: Space.m), child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.palette.error))),
      ],
    );
  }
}

Uint8List? _rotateJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return Uint8List.fromList(img.encodeJpg(img.copyRotate(decoded, angle: 90), quality: 88));
}

// ---------------------------------------------------------------- 14 Processing

class ReceiptProcessingScreen extends ConsumerWidget {
  const ReceiptProcessingScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(receiptProvider(receiptId), (_, next) {
      final r = next.value;
      if (r == null) return;
      switch (r.status) {
        case ReceiptStatus.needsReview:
          context.pushReplacement('/receipt/$receiptId/review');
        case ReceiptStatus.failed || ReceiptStatus.duplicate:
          context.pushReplacement('/receipt/$receiptId/error');
        case ReceiptStatus.imported:
          context.pushReplacement('/receipt/$receiptId/done');
        default:
      }
    });
    final r = ref.watch(receiptProvider(receiptId)).value;
    final progress = r?.progress ?? 0;
    final steps = [
      ('Uploading securely', r != null && r.status != ReceiptStatus.uploading),
      ('Reading every line', progress >= 0.6),
      ('Checking totals and duplicates', progress >= 0.9),
      ('Matching to your kitchen', r?.status == ReceiptStatus.needsReview),
    ];
    final reduceMotion = context.reduceMotion;
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Receipt', title: 'Reading your receipt', subtitle: 'This usually takes under a minute. You can leave — we\'ll keep going.'),
      primaryAction: SecondaryActionButton(
        label: 'Cancel',
        onPressed: () async {
          final hid = ref.read(householdIdProvider);
          if (hid != null) await ref.read(receiptRepoProvider).cancel(hid, receiptId);
          if (context.mounted) context.pop();
        },
      ),
      children: [
        const SizedBox(height: Space.l),
        Semantics(
          label: 'Progress ${(progress * 100).round()} percent',
          child: LinearProgressIndicator(value: reduceMotion || progress == 0 ? (progress == 0 ? null : progress) : progress, minHeight: 6),
        ),
        const SizedBox(height: Space.xl),
        for (final (label, done) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Row(children: [
              Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? context.palette.success : context.palette.muted),
              const SizedBox(width: Space.s),
              Text(label, style: context.text.bodyLarge?.copyWith(color: done ? context.palette.ink : context.palette.muted)),
            ]),
          ),
        const SizedBox(height: Space.l),
        TextButton(onPressed: () => context.go('/today'), child: const Text('Continue in the background')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 15 Review purchases

class ReceiptReviewScreen extends ConsumerWidget {
  const ReceiptReviewScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receiptProvider(receiptId));
    final r = async.value;
    if (r == null) return PremiumAppScaffold(children: [async.isLoading ? const LoadingState() : const ErrorState(message: 'Receipt not found.')]);
    if (r.status == ReceiptStatus.imported) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.task_alt, title: 'Already in your kitchen', message: 'This receipt was imported.', actionLabel: 'See summary', onAction: () => context.pushReplacement('/receipt/$receiptId/done')),
      ]);
    }
    final blocking = ReceiptImportService.blockingLines(r);
    final review = r.lines.where((l) => l.needsReview).length;
    final linesTotal = r.linesTotal;
    final totalsMatch = r.subtotal == null || (linesTotal.minorUnits - r.subtotal!.minorUnits).abs() <= 2;

    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: r.merchant ?? 'Receipt',
        title: 'Review purchases',
        subtitle: '${r.activeLines.length} items${review == 0 ? '' : ' · $review to check'}',
      ),
      primaryAction: PrimaryActionButton(
        label: blocking.isNotEmpty ? 'Resolve ${blocking.length} item${blocking.length == 1 ? '' : 's'}' : 'Continue',
        onPressed: () => context.push(blocking.isNotEmpty ? '/receipt/$receiptId/unknown' : '/receipt/$receiptId/storage'),
      ),
      children: [
        if (r.isDemo) const DemoBanner(message: 'Demo: this is a built-in sample receipt, not your photo.'),
        SoftCard(
          color: totalsMatch ? context.palette.successSoft : context.palette.warningSoft,
          child: Row(children: [
            Icon(totalsMatch ? Icons.verified_outlined : Icons.warning_amber_rounded, color: totalsMatch ? context.palette.success : context.palette.warning),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                totalsMatch
                    ? 'Items add up to the receipt subtotal${r.total == null ? '' : ' · total ${r.total!.format()}'}.'
                    : 'Items add up to ${linesTotal.format()} but the subtotal reads ${r.subtotal!.format()}. A line may be missing — you can add it.',
                style: context.text.bodySmall?.copyWith(color: context.palette.ink),
              ),
            ),
          ]),
        ),
        const SizedBox(height: Space.m),
        for (final l in r.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: _LineTile(line: l, onTap: () => showCorrectItemSheet(context, ref, r, l), onToggle: (excluded) => _saveLine(ref, r, l.copyWith(excluded: excluded))),
          ),
        TextButton.icon(onPressed: () => showCorrectItemSheet(context, ref, r, null), icon: const Icon(Icons.add), label: const Text('Add a missing item')),
      ],
    );
  }
}

Future<void> _saveLine(WidgetRef ref, PurchaseReceipt r, ReceiptLineItem updated) async {
  final lines = [for (final l in r.lines) l.id == updated.id ? updated : l];
  if (!lines.any((l) => l.id == updated.id)) lines.add(updated);
  await ref.read(receiptRepoProvider).saveLines(r.householdId, r.id, lines);
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onTap, required this.onToggle});
  final ReceiptLineItem line;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = line;
    return Card(
      color: l.excluded ? p.background : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  l.name.isEmpty ? 'Unknown item' : l.name,
                  style: context.text.titleMedium?.copyWith(
                    decoration: l.excluded ? TextDecoration.lineThrough : null,
                    color: l.excluded ? p.muted : null,
                  ),
                ),
                Text(l.rawText, style: context.text.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 4),
                Wrap(spacing: Space.xs, runSpacing: 4, children: [
                  TagPill(l.quantity?.format() ?? 'Amount needed', color: l.quantity == null ? p.warning : null, background: l.quantity == null ? p.warningSoft : null),
                  if (l.totalPrice != null) TagPill(l.totalPrice!.format()),
                  if (!l.isFood) TagPill('Not food', icon: Icons.cleaning_services_outlined),
                  if (l.userEdited) TagPill('Checked', icon: Icons.check, color: p.success, background: p.successSoft)
                  else if (l.needsReview) TagPill('Please check', icon: Icons.help_outline, color: p.warning, background: p.warningSoft),
                ]),
              ]),
            ),
            Semantics(
              label: l.excluded ? 'Excluded. Tap to include' : 'Included. Tap to exclude',
              child: Switch(value: !l.excluded, onChanged: (v) => onToggle(!v)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 16 Correct item

Future<void> showCorrectItemSheet(BuildContext context, WidgetRef ref, PurchaseReceipt r, ReceiptLineItem? line) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CorrectItemSheet(receipt: r, line: line),
    );

class CorrectItemSheet extends ConsumerStatefulWidget {
  const CorrectItemSheet({super.key, required this.receipt, this.line});
  final PurchaseReceipt receipt;
  final ReceiptLineItem? line;

  @override
  ConsumerState<CorrectItemSheet> createState() => _CorrectItemSheetState();
}

class _CorrectItemSheetState extends ConsumerState<CorrectItemSheet> {
  late final _name = TextEditingController(text: widget.line?.name ?? '');
  late final _brand = TextEditingController(text: widget.line?.brand ?? '');
  late final _package = TextEditingController(text: widget.line?.packageDescription ?? '');
  late FoodCategory _category = widget.line?.category ?? FoodCategory.other;
  late Quantity _qty = widget.line?.quantity ?? const Quantity(1, Unit.piece);
  late StorageKind _storage = widget.line?.storage ?? StorageKind.pantry;
  late bool _isFood = widget.line?.isFood ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _package.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isFood && _name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final base = widget.line ??
          ReceiptLineItem(
            id: 'u${DateTime.now().microsecondsSinceEpoch}',
            rawText: '(added by you)',
            name: '',
            category: FoodCategory.other,
            confidence: 1,
          );
      final updated = base.copyWith(
        name: _name.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        packageDescription: _package.text.trim().isEmpty ? null : _package.text.trim(),
        category: _isFood ? _category : FoodCategory.nonFood,
        quantity: _qty,
        storage: _storage,
        isFood: _isFood,
        excluded: !_isFood,
        userEdited: true,
        issues: const [],
        // A corrected name must be re-matched to the catalogue.
        matchedProductId: _name.text.trim() == base.name ? base.matchedProductId : '',
      );
      await _save2(updated.matchedProductId == '' ? _clearMatch(updated) : updated);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ReceiptLineItem _clearMatch(ReceiptLineItem l) => ReceiptLineItem.fromMap(l.toMap()..remove('matchedProductId'));

  Future<void> _save2(ReceiptLineItem l) => _saveLine(ref, widget.receipt, l);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.line == null ? 'Add an item' : 'Correct item', style: context.text.headlineSmall),
          if (widget.line != null) Text('Receipt says: ${widget.line!.rawText}', style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('This is food'),
            subtitle: const Text('Non-food purchases are not added to your kitchen'),
            value: _isFood,
            onChanged: (v) => setState(() => _isFood = v),
          ),
          TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Product name')),
          const SizedBox(height: Space.s),
          if (_isFood) ...[
            TextField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
            const SizedBox(height: Space.s),
            TextField(controller: _package, decoration: const InputDecoration(labelText: 'Package size (optional)', hintText: 'e.g. 750 g tub')),
            const SizedBox(height: Space.m),
            Text('Quantity', style: context.text.titleSmall),
            const SizedBox(height: Space.xs),
            Row(children: [
              QuantityStepper(value: _qty, min: 0.001, onChanged: (q) => setState(() => _qty = q)),
              const SizedBox(width: Space.s),
              DropdownButton<Unit>(
                value: _qty.unit,
                items: [for (final u in Unit.values) DropdownMenuItem(value: u, child: Text(u.symbol))],
                onChanged: (u) => setState(() => _qty = Quantity(_qty.amount, u!)),
              ),
            ]),
            const SizedBox(height: Space.m),
            DropdownButtonFormField<FoodCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in FoodCategory.values.where((c) => c != FoodCategory.nonFood)) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (c) => setState(() => _category = c!),
            ),
            const SizedBox(height: Space.m),
            Text('Store in', style: context.text.titleSmall),
            Wrap(spacing: Space.xs, children: [
              for (final s in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry])
                ChoiceChip(label: Text(s.label), selected: _storage == s, onSelected: (_) => setState(() => _storage = s)),
            ]),
          ],
          const SizedBox(height: Space.l),
          PrimaryActionButton(label: 'Save', loading: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- 17 Unknown items

class UnknownItemsScreen extends ConsumerWidget {
  const UnknownItemsScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(receiptProvider(receiptId)).value;
    if (r == null) return const Scaffold(body: LoadingState());
    final unresolved = r.lines.where((l) => !l.excluded && (l.needsReview || ReceiptImportService.blockingLines(r).contains(l))).toList();
    final blocking = ReceiptImportService.blockingLines(r);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Receipt', title: 'A few to check', subtitle: unresolved.isEmpty ? 'All resolved.' : 'Tell us what these are, or leave them out.'),
      primaryAction: PrimaryActionButton(
        label: blocking.isEmpty ? 'Continue' : '${blocking.length} still need a name and amount',
        onPressed: blocking.isEmpty ? () => context.pushReplacement('/receipt/$receiptId/storage') : null,
      ),
      children: [
        if (unresolved.isEmpty) const EmptyState(icon: Icons.task_alt, title: 'Nothing left to check', message: 'Everything has a name and an amount.', compact: true),
        for (final l in unresolved)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.rawText, style: context.text.bodySmall?.copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(l.name.isEmpty ? 'We couldn\'t tell what this is' : 'Looks like: ${l.name}${l.quantity == null ? ' (amount unknown)' : ' · ${l.quantity!.format()}'}', style: context.text.titleMedium),
                for (final issue in l.issues) Text(issue, style: context.text.bodySmall),
                const SizedBox(height: Space.s),
                Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
                  FilledButton.tonal(onPressed: () => showCorrectItemSheet(context, ref, r, l), child: const Text('Fix')),
                  if (l.name.isNotEmpty && l.quantity != null)
                    OutlinedButton(onPressed: () => _saveLine(ref, r, l.copyWith(userEdited: true, issues: const [])), child: const Text('Looks right')),
                  OutlinedButton(onPressed: () => _saveLine(ref, r, l.copyWith(isFood: false, excluded: true, userEdited: true)), child: const Text('Not food')),
                  TextButton(onPressed: () => _saveLine(ref, r, l.copyWith(excluded: true)), child: const Text('Leave out')),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 18 Storage assignment

class StorageAssignmentScreen extends ConsumerStatefulWidget {
  const StorageAssignmentScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  ConsumerState<StorageAssignmentScreen> createState() => _StorageAssignmentScreenState();
}

class _StorageAssignmentScreenState extends ConsumerState<StorageAssignmentScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _import(PurchaseReceipt r) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(actionsProvider).confirmReceipt(r);
      if (mounted) context.go('/receipt/${r.id}/done');
    } on ReceiptValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = ErrorState.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(receiptProvider(widget.receiptId)).value;
    if (r == null) return const Scaffold(body: LoadingState());
    final food = r.lines.where((l) => !l.excluded && l.isFood).toList();
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Receipt', title: 'Where does it go?', subtitle: 'We\'ve suggested a spot for each. Tap to change.'),
      primaryAction: PrimaryActionButton(label: 'Add ${food.length} item${food.length == 1 ? '' : 's'} to kitchen', loading: _busy, onPressed: food.isEmpty ? null : () => _import(r)),
      children: [
        for (final kind in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry]) ...[
          if (food.any((l) => l.storage == kind)) SectionHeader(kind.label, topSpacing: Space.s),
          for (final l in food.where((l) => l.storage == kind))
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: Row(children: [
                  Expanded(child: Text('${l.name} · ${l.quantity?.format() ?? ''}', style: context.text.bodyLarge)),
                  PopupMenuButton<StorageKind>(
                    tooltip: 'Change storage',
                    initialValue: l.storage,
                    onSelected: (k) => _saveLine(ref, r, l.copyWith(storage: k)),
                    itemBuilder: (_) => [for (final k in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry]) PopupMenuItem(value: k, child: Text(k.label))],
                    child: Padding(padding: const EdgeInsets.all(Space.xs), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(l.storage.label), const Icon(Icons.expand_more)])),
                  ),
                ]),
              ),
            ),
        ],
        if (food.any((l) => l.storage == StorageKind.custom))
          for (final l in food.where((l) => l.storage == StorageKind.custom))
            ListTile(title: Text(l.name), trailing: TextButton(onPressed: () => _saveLine(ref, r, l.copyWith(storage: StorageKind.pantry)), child: const Text('Pantry'))),
        if (_error != null) Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.palette.error)),
      ],
    );
  }
}

// ---------------------------------------------------------------- 19 Error / duplicate

class ReceiptErrorScreen extends ConsumerWidget {
  const ReceiptErrorScreen({super.key, required this.receiptId, this.reason});
  final String receiptId;
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(receiptProvider(receiptId)).value;
    final duplicate = reason == 'duplicate' || r?.status == ReceiptStatus.duplicate;
    if (duplicate) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(eyebrow: 'Receipt', title: 'Already scanned?'),
        primaryAction: PrimaryActionButton(label: 'View the earlier receipt', onPressed: () => context.pushReplacement(r?.status == ReceiptStatus.imported ? '/receipt/$receiptId/done' : '/receipt/$receiptId/review')),
        children: [
          EmptyState(
            icon: Icons.copy_all_outlined,
            title: 'This looks like a receipt you\'ve already added',
            message: 'To avoid counting groceries twice, we stopped here.${r == null ? '' : ' Earlier scan: ${formatDay(r.createdAt)}.'}',
            secondaryLabel: 'It\'s a different receipt — continue',
            onSecondary: () async {
              final pages = ref.read(receiptDraftProvider);
              if (pages.isEmpty) return context.pop();
              final id = await ref.read(actionsProvider).submitReceipt(pages, allowDuplicate: true);
              ref.read(receiptDraftProvider.notifier).clear();
              if (context.mounted) context.pushReplacement('/receipt/$id/processing');
            },
          ),
        ],
      );
    }
    final quality = r?.errorCode == 'unreadable' || r?.errorCode == 'not_a_receipt';
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Receipt', title: 'We couldn\'t read that one'),
      primaryAction: PrimaryActionButton(label: quality ? 'Retake photo' : 'Try again', onPressed: () async {
        if (quality) {
          context.pushReplacement('/receipt/capture');
        } else {
          await ref.read(actionsProvider).retryReceipt(receiptId);
          if (context.mounted) context.pushReplacement('/receipt/$receiptId/processing');
        }
      }),
      children: [
        EmptyState(
          icon: Icons.blur_on,
          title: r?.errorMessage ?? 'Something went wrong',
          message: quality
              ? 'The photo may be blurry, too dark or cut off. Lay the receipt flat in bright light and include the whole thing.'
              : 'Nothing was added to your kitchen, so it\'s safe to retry.',
          secondaryLabel: 'Add items by hand instead',
          onSecondary: () => context.pushReplacement('/kitchen/add'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 20 Import complete

class ReceiptDoneScreen extends ConsumerWidget {
  const ReceiptDoneScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(receiptProvider(receiptId)).value;
    if (r == null) return const Scaffold(body: LoadingState());
    final s = ReceiptSummary(r);
    return PremiumAppScaffold(
      showBack: false,
      header: EditorialPageHeader(eyebrow: r.merchant ?? 'Receipt', title: 'Your kitchen is up to date'),
      primaryAction: PrimaryActionButton(label: 'View kitchen', onPressed: () => context.go('/kitchen')),
      children: [
        Row(children: [
          Expanded(child: _Metric(value: '${s.imported}', label: 'items added')),
          Expanded(child: _Metric(value: '${s.excluded}', label: 'left out')),
          Expanded(child: _Metric(value: s.total?.format() ?? '—', label: 'total')),
        ]),
        const SizedBox(height: Space.l),
        if (s.estimated > 0)
          SoftCard(
            color: context.palette.infoSoft,
            child: Text('${s.estimated} item${s.estimated == 1 ? ' is' : 's are'} marked as estimated. Chefii will ask you to confirm next time you\'re in the kitchen.',
                style: context.text.bodySmall?.copyWith(color: context.palette.ink)),
          ),
        if (r.importOperationId != null) ...[
          const SizedBox(height: Space.s),
          TextButton.icon(
            icon: const Icon(Icons.undo),
            label: const Text('Undo this import'),
            onPressed: () async {
              final ok = await showConfirmActionSheet(context,
                  title: 'Undo import?', message: 'Removes these items from your kitchen. Anything already used stays recorded.', confirmLabel: 'Undo import', destructive: true);
              if (!ok) return;
              try {
                final res = await ref.read(actionsProvider).undo(r.importOperationId!);
                if (context.mounted) showMessage(context, res.operation.summary);
              } catch (e) {
                if (context.mounted) showMessage(context, ErrorState.describe(e), error: true);
              }
            },
          ),
        ],
        const SizedBox(height: Space.s),
        SecondaryActionButton(icon: Icons.receipt_long_outlined, label: 'Scan another receipt', onPressed: () => context.pushReplacement('/receipt/capture')),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(children: [
          Text(value, style: context.text.headlineMedium),
          Text(label, style: context.text.bodySmall),
        ]),
      );
}

/// Receipts list (history) — reachable from the kitchen.
class ReceiptsListScreen extends ConsumerWidget {
  const ReceiptsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider).value ?? const <PurchaseReceipt>[];
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Kitchen', title: 'Receipts'),
      primaryAction: PrimaryActionButton(label: 'Scan a receipt', onPressed: () => context.push('/receipt/capture')),
      children: [
        if (receipts.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No receipts yet', message: 'Scanned receipts appear here.'),
        for (final r in receipts)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(r.merchant ?? 'Receipt'),
              subtitle: Text('${formatDay(r.createdAt)} · ${r.status.label}${r.total == null ? '' : ' · ${r.total!.format()}'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(switch (r.status) {
                ReceiptStatus.needsReview => '/receipt/${r.id}/review',
                ReceiptStatus.imported => '/receipt/${r.id}/done',
                ReceiptStatus.failed || ReceiptStatus.duplicate => '/receipt/${r.id}/error',
                ReceiptStatus.uploading || ReceiptStatus.uploaded || ReceiptStatus.processing => '/receipt/${r.id}/processing',
                ReceiptStatus.cancelled => '/receipt/${r.id}/error',
              }),
            ),
          ),
      ],
    );
  }
}

/// Re-export for screens that offer "Tell Chefii".
const showCommandSheet = showKitchenCommandSheet;
