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
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/receipt.dart';
import '../../domain/units/units.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../kitchen/kitchen_sheets.dart';
import '../shared/ai_consent.dart';
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
    final l10n = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l10n.receiptsEyebrow,
        title: l10n.receiptsCaptureTitle,
        subtitle: l10n.receiptsCaptureSubtitle,
      ),
      primaryAction: PrimaryActionButton(
        icon: Icons.document_scanner_outlined,
        label: _hasDocScanner ? l10n.receiptsScanReceipt : l10n.receiptsTakePhoto,
        loading: _busy,
        onPressed: _hasDocScanner ? _scanDocument : () => _photo(true),
      ),
      children: [
        if (isDemo) DemoBanner(message: l10n.receiptsDemoCapture),
        if (_denied)
          PermissionDeniedState(
            permission: l10n.receiptsCameraPermission,
            why: l10n.receiptsCameraWhy,
            alternativeLabel: l10n.receiptsImportPhoto,
            onAlternative: () => _photo(false),
          ),
        FoodArtwork(artKey: 'cream', height: 200, label: l10n.receiptsArtworkLabel),
        const SizedBox(height: Space.l),
        for (final (icon, text) in [
          (Icons.light_mode_outlined, l10n.receiptsTipLight),
          (Icons.crop_free, l10n.receiptsTipFrame),
          (Icons.layers_outlined, l10n.receiptsTipPages),
          (Icons.lock_outline, l10n.receiptsTipPrivacy),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: context.colors.primary),
                const SizedBox(width: Space.s),
                Expanded(child: Text(text, style: context.text.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: Space.s),
        if (_hasDocScanner)
          TextButton.icon(
            onPressed: _busy ? null : () => _photo(true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(l10n.receiptsRegularCamera),
          ),
        TextButton.icon(onPressed: _busy ? null : () => _photo(false), icon: const Icon(Icons.photo_library_outlined), label: Text(l10n.receiptsImportFromPhotos)),
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
    if (!await ensureAiConsent(context, ref, feature: context.l10n.receiptsAiFeature)) return;
    if (!mounted) return;
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
    final l10n = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l10n.receiptsEyebrow,
        title: l10n.receiptsPreviewTitle,
        subtitle: l10n.receiptsPreviewSubtitle(pages.length),
      ),
      primaryAction: PrimaryActionButton(label: l10n.receiptsAnalyze, loading: _busy, onPressed: pages.isEmpty ? null : _analyze),
      children: [
        if (pages.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: l10n.receiptsNoPagesTitle,
            message: l10n.receiptsNoPagesMessage,
            actionLabel: l10n.receiptsCapture,
            onAction: () => context.pop(),
          ),
        for (var i = 0; i < pages.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: Space.s),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Semantics(
                  image: true,
                  label: l10n.receiptsPageSemantics(i + 1),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: Image.memory(pages[i].bytes, fit: BoxFit.contain, width: double.infinity, gaplessPlayback: true),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: Space.m),
                    Text(l10n.receiptsPageLabel(i + 1), style: context.text.labelMedium),
                    const Spacer(),
                    IconButton(tooltip: l10n.receiptsRotate, onPressed: _busy ? null : () => _rotate(i), icon: const Icon(Icons.rotate_right)),
                    IconButton(
                      tooltip: l10n.receiptsRetake,
                      onPressed: _busy
                          ? null
                          : () async {
                              final p = await pickPhoto(camera: true);
                              if (p != null) ref.read(receiptDraftProvider.notifier).replace(i, p);
                            },
                      icon: const Icon(Icons.replay),
                    ),
                    IconButton(
                      tooltip: l10n.receiptsRemovePage,
                      onPressed: _busy ? null : () => ref.read(receiptDraftProvider.notifier).removeAt(i),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (pages.isNotEmpty && pages.length < ReceiptImageRules.maxPages)
          SecondaryActionButton(
            icon: Icons.add_photo_alternate_outlined,
            label: l10n.receiptsAddPage,
            onPressed: _busy
                ? null
                : () async {
                    final p = await pickPhoto(camera: true);
                    if (p != null) ref.read(receiptDraftProvider.notifier).add(p);
                  },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.palette.error)),
          ),
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
    final l10n = context.l10n;
    final steps = [
      (l10n.receiptsStepUploading, r != null && r.status != ReceiptStatus.uploading),
      (l10n.receiptsStepReading, progress >= 0.6),
      (l10n.receiptsStepChecking, progress >= 0.9),
      (l10n.receiptsStepMatching, r?.status == ReceiptStatus.needsReview),
    ];
    final reduceMotion = context.reduceMotion;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l10n.receiptsEyebrow,
        title: l10n.receiptsProcessingTitle,
        subtitle: l10n.receiptsProcessingSubtitle,
      ),
      primaryAction: SecondaryActionButton(
        label: l10n.commonCancel,
        onPressed: () async {
          final hid = ref.read(householdIdProvider);
          if (hid != null) await ref.read(receiptRepoProvider).cancel(hid, receiptId);
          if (context.mounted) context.pop();
        },
      ),
      children: [
        const SizedBox(height: Space.l),
        Semantics(
          label: l10n.receiptsProgressSemantics((progress * 100).round()),
          child: LinearProgressIndicator(value: reduceMotion || progress == 0 ? (progress == 0 ? null : progress) : progress, minHeight: 6),
        ),
        const SizedBox(height: Space.xl),
        for (final (label, done) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Row(
              children: [
                Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? context.palette.success : context.palette.muted),
                const SizedBox(width: Space.s),
                Text(label, style: context.text.bodyLarge?.copyWith(color: done ? context.palette.ink : context.palette.muted)),
              ],
            ),
          ),
        const SizedBox(height: Space.l),
        TextButton(onPressed: () => context.go('/today'), child: Text(l10n.receiptsContinueBackground)),
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
    final l10n = context.l10n;
    if (r == null) return PremiumAppScaffold(children: [async.isLoading ? const LoadingState() : ErrorState(message: l10n.receiptsNotFound)]);
    if (r.status == ReceiptStatus.imported) {
      return PremiumAppScaffold(
        children: [
          EmptyState(
            icon: Icons.task_alt,
            title: l10n.receiptsAlreadyInKitchenTitle,
            message: l10n.receiptsAlreadyImportedMessage,
            actionLabel: l10n.receiptsSeeSummary,
            onAction: () => context.pushReplacement('/receipt/$receiptId/done'),
          ),
        ],
      );
    }
    final blocking = ReceiptImportService.blockingLines(r);
    final review = r.lines.where((l) => l.needsReview).length;
    final linesTotal = r.linesTotal;
    final totalsMatch = r.subtotal == null || (linesTotal.minorUnits - r.subtotal!.minorUnits).abs() <= 2;

    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: r.merchant ?? l10n.receiptsEyebrow,
        title: l10n.receiptsReviewTitle,
        subtitle: review == 0 ? l10n.receiptsReviewSubtitle(r.activeLines.length) : l10n.receiptsReviewSubtitleToCheck(r.activeLines.length, review),
      ),
      primaryAction: PrimaryActionButton(
        label: blocking.isNotEmpty ? l10n.receiptsResolveItems(blocking.length) : l10n.commonContinue,
        onPressed: () => context.push(blocking.isNotEmpty ? '/receipt/$receiptId/unknown' : '/receipt/$receiptId/storage'),
      ),
      children: [
        if (r.isDemo) DemoBanner(message: l10n.receiptsDemoReview),
        SoftCard(
          color: totalsMatch ? context.palette.successSoft : context.palette.warningSoft,
          child: Row(
            children: [
              Icon(totalsMatch ? Icons.verified_outlined : Icons.warning_amber_rounded, color: totalsMatch ? context.palette.success : context.palette.warning),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  totalsMatch
                      ? (r.total == null ? l10n.receiptsTotalsMatch : l10n.receiptsTotalsMatchWithTotal(_formatMoney(context, r.total!)))
                      : l10n.receiptsTotalsMismatch(_formatMoney(context, linesTotal), _formatMoney(context, r.subtotal!)),
                  style: context.text.bodySmall?.copyWith(color: context.palette.ink),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.m),
        for (final l in r.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: _LineTile(
              line: l,
              onTap: () => showCorrectItemSheet(context, ref, r, l),
              onToggle: (excluded) => _saveLine(ref, r, l.copyWith(excluded: excluded)),
            ),
          ),
        TextButton.icon(onPressed: () => showCorrectItemSheet(context, ref, r, null), icon: const Icon(Icons.add), label: Text(l10n.receiptsAddMissingItem)),
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
    final l10n = context.l10n;
    return Card(
      color: l.excluded ? p.background : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.l),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.name.isEmpty ? l10n.receiptsUnknownItem : l.name,
                      style: context.text.titleMedium?.copyWith(decoration: l.excluded ? TextDecoration.lineThrough : null, color: l.excluded ? p.muted : null),
                    ),
                    Text(l.rawText, style: context.text.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 12)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: 4,
                      children: [
                        TagPill(
                          l.quantity == null ? l10n.receiptsAmountNeeded : context.formatQty(l.quantity!),
                          color: l.quantity == null ? p.warning : null,
                          background: l.quantity == null ? p.warningSoft : null,
                        ),
                        if (l.totalPrice != null) TagPill(_formatMoney(context, l.totalPrice!)),
                        if (!l.isFood) TagPill(l10n.receiptsNotFood, icon: Icons.cleaning_services_outlined),
                        if (l.userEdited)
                          TagPill(l10n.receiptsChecked, icon: Icons.check, color: p.success, background: p.successSoft)
                        else if (l.needsReview)
                          TagPill(l10n.receiptsPleaseCheck, icon: Icons.help_outline, color: p.warning, background: p.warningSoft),
                      ],
                    ),
                  ],
                ),
              ),
              Semantics(
                label: l.excluded ? l10n.receiptsExcludedSemantics : l10n.receiptsIncludedSemantics,
                child: Switch(value: !l.excluded, onChanged: (v) => onToggle(!v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 16 Correct item

Future<void> showCorrectItemSheet(BuildContext context, WidgetRef ref, PurchaseReceipt r, ReceiptLineItem? line) => showModalBottomSheet(
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
      final base =
          widget.line ??
          ReceiptLineItem(id: 'u${DateTime.now().microsecondsSinceEpoch}', rawText: context.l10n.receiptsAddedByYou, name: '', category: FoodCategory.other, confidence: 1);
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
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.line == null ? l10n.receiptsAddItemTitle : l10n.receiptsCorrectItemTitle, style: context.text.headlineSmall),
            if (widget.line != null) Text(l10n.receiptsReceiptSays(widget.line!.rawText), style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.receiptsIsFood),
              subtitle: Text(l10n.receiptsIsFoodSubtitle),
              value: _isFood,
              onChanged: (v) => setState(() => _isFood = v),
            ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.receiptsProductName),
            ),
            const SizedBox(height: Space.s),
            if (_isFood) ...[
              TextField(
                controller: _brand,
                decoration: InputDecoration(labelText: l10n.receiptsBrandOptional),
              ),
              const SizedBox(height: Space.s),
              TextField(
                controller: _package,
                decoration: InputDecoration(labelText: l10n.receiptsPackageOptional, hintText: l10n.receiptsPackageHint),
              ),
              const SizedBox(height: Space.m),
              Text(l10n.receiptsQuantity, style: context.text.titleSmall),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  QuantityStepper(value: _qty, min: 0.001, onChanged: (q) => setState(() => _qty = q)),
                  const SizedBox(width: Space.s),
                  DropdownButton<Unit>(
                    value: _qty.unit,
                    items: [for (final u in Unit.values) DropdownMenuItem(value: u, child: Text(context.labelOf(u)))],
                    onChanged: (u) => setState(() => _qty = Quantity(_qty.amount, u!)),
                  ),
                ],
              ),
              const SizedBox(height: Space.m),
              DropdownButtonFormField<FoodCategory>(
                isExpanded: true,
                initialValue: _category,
                decoration: InputDecoration(labelText: l10n.receiptsCategory),
                items: [for (final c in FoodCategory.values.where((c) => c != FoodCategory.nonFood)) DropdownMenuItem(value: c, child: Text(context.labelOf(c)))],
                onChanged: (c) => setState(() => _category = c!),
              ),
              const SizedBox(height: Space.m),
              Text(l10n.receiptsStoreIn, style: context.text.titleSmall),
              Wrap(
                spacing: Space.xs,
                children: [
                  for (final s in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry])
                    ChoiceChip(label: Text(context.labelOf(s)), selected: _storage == s, onSelected: (_) => setState(() => _storage = s)),
                ],
              ),
            ],
            const SizedBox(height: Space.l),
            PrimaryActionButton(label: l10n.commonSave, loading: _busy, onPressed: _save),
          ],
        ),
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
    final l10n = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l10n.receiptsEyebrow,
        title: l10n.receiptsUnknownTitle,
        subtitle: unresolved.isEmpty ? l10n.receiptsAllResolved : l10n.receiptsUnknownSubtitle,
      ),
      primaryAction: PrimaryActionButton(
        label: blocking.isEmpty ? l10n.commonContinue : l10n.receiptsStillNeedNameAmount(blocking.length),
        onPressed: blocking.isEmpty ? () => context.pushReplacement('/receipt/$receiptId/storage') : null,
      ),
      children: [
        if (unresolved.isEmpty)
          EmptyState(icon: Icons.task_alt, title: l10n.receiptsNothingLeftTitle, message: l10n.receiptsNothingLeftMessage, compact: true),
        for (final l in unresolved)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.rawText, style: context.text.bodySmall?.copyWith(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text(
                    l.name.isEmpty
                        ? l10n.receiptsCouldntTell
                        : l.quantity == null
                        ? l10n.receiptsLooksLikeUnknownAmount(l.name)
                        : l10n.receiptsLooksLikeWithAmount(l.name, context.formatQty(l.quantity!)),
                    style: context.text.titleMedium,
                  ),
                  for (final issue in l.issues) Text(issue, style: context.text.bodySmall),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      FilledButton.tonal(onPressed: () => showCorrectItemSheet(context, ref, r, l), child: Text(l10n.receiptsFix)),
                      if (l.name.isNotEmpty && l.quantity != null)
                        OutlinedButton(
                          onPressed: () => _saveLine(ref, r, l.copyWith(userEdited: true, issues: const [])),
                          child: Text(l10n.receiptsLooksRight),
                        ),
                      OutlinedButton(
                        onPressed: () => _saveLine(ref, r, l.copyWith(isFood: false, excluded: true, userEdited: true)),
                        child: Text(l10n.receiptsNotFood),
                      ),
                      TextButton(onPressed: () => _saveLine(ref, r, l.copyWith(excluded: true)), child: Text(l10n.receiptsLeaveOut)),
                    ],
                  ),
                ],
              ),
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
    final l10n = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l10n.receiptsEyebrow, title: l10n.receiptsStorageTitle, subtitle: l10n.receiptsStorageSubtitle),
      primaryAction: PrimaryActionButton(
        label: l10n.receiptsAddToKitchen(food.length),
        loading: _busy,
        onPressed: food.isEmpty ? null : () => _import(r),
      ),
      children: [
        for (final kind in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry]) ...[
          if (food.any((l) => l.storage == kind)) SectionHeader(context.labelOf(kind), topSpacing: Space.s),
          for (final l in food.where((l) => l.storage == kind))
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: Row(
                  children: [
                    Expanded(child: Text([l.name, if (l.quantity != null) context.formatQty(l.quantity!)].join(' · '), style: context.text.bodyLarge)),
                    PopupMenuButton<StorageKind>(
                      tooltip: l10n.receiptsChangeStorage,
                      initialValue: l.storage,
                      onSelected: (k) => _saveLine(ref, r, l.copyWith(storage: k)),
                      itemBuilder: (_) => [
                        for (final k in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry]) PopupMenuItem(value: k, child: Text(context.labelOf(k))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xs),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(context.labelOf(l.storage)), const Icon(Icons.expand_more)]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (food.any((l) => l.storage == StorageKind.custom))
          for (final l in food.where((l) => l.storage == StorageKind.custom))
            ListTile(
              title: Text(l.name),
              trailing: TextButton(
                onPressed: () => _saveLine(ref, r, l.copyWith(storage: StorageKind.pantry)),
                child: Text(context.labelOf(StorageKind.pantry)),
              ),
            ),
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
    final l10n = context.l10n;
    if (duplicate) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(eyebrow: l10n.receiptsEyebrow, title: l10n.receiptsDuplicateTitle),
        primaryAction: PrimaryActionButton(
          label: l10n.receiptsViewEarlier,
          onPressed: () => context.pushReplacement(r?.status == ReceiptStatus.imported ? '/receipt/$receiptId/done' : '/receipt/$receiptId/review'),
        ),
        children: [
          EmptyState(
            icon: Icons.copy_all_outlined,
            title: l10n.receiptsDuplicateHeadline,
            message: r == null ? l10n.receiptsDuplicateMessage : l10n.receiptsDuplicateMessageWithDate(formatDay(context, r.createdAt)),
            secondaryLabel: l10n.receiptsDifferentReceipt,
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
      header: EditorialPageHeader(eyebrow: l10n.receiptsEyebrow, title: l10n.receiptsErrorTitle),
      primaryAction: PrimaryActionButton(
        label: quality ? l10n.receiptsRetakePhoto : l10n.commonTryAgain,
        onPressed: () async {
          if (quality) {
            context.pushReplacement('/receipt/capture');
          } else {
            await ref.read(actionsProvider).retryReceipt(receiptId);
            if (context.mounted) context.pushReplacement('/receipt/$receiptId/processing');
          }
        },
      ),
      children: [
        EmptyState(
          icon: Icons.blur_on,
          title: r?.errorMessage ?? l10n.receiptsSomethingWrong,
          message: quality ? l10n.receiptsQualityMessage : l10n.receiptsSafeRetry,
          secondaryLabel: l10n.receiptsAddByHand,
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
    final l10n = context.l10n;
    return PremiumAppScaffold(
      showBack: false,
      header: EditorialPageHeader(eyebrow: r.merchant ?? l10n.receiptsEyebrow, title: l10n.receiptsDoneTitle),
      primaryAction: PrimaryActionButton(label: l10n.receiptsViewKitchen, onPressed: () => context.go('/kitchen')),
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(value: '${s.imported}', label: l10n.receiptsMetricAdded(s.imported)),
            ),
            Expanded(
              child: _Metric(value: '${s.excluded}', label: l10n.receiptsMetricLeftOut(s.excluded)),
            ),
            Expanded(
              child: _Metric(value: s.total == null ? '—' : _formatMoney(context, s.total!), label: l10n.receiptsMetricTotal),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        if (s.estimated > 0)
          SoftCard(
            color: context.palette.infoSoft,
            child: Text(
              l10n.receiptsEstimatedNote(s.estimated),
              style: context.text.bodySmall?.copyWith(color: context.palette.ink),
            ),
          ),
        if (r.importOperationId != null) ...[
          const SizedBox(height: Space.s),
          TextButton.icon(
            icon: const Icon(Icons.undo),
            label: Text(l10n.receiptsUndoImportButton),
            onPressed: () async {
              final ok = await showConfirmActionSheet(
                context,
                title: l10n.receiptsUndoImportTitle,
                message: l10n.receiptsUndoImportMessage,
                confirmLabel: l10n.receiptsUndoImportConfirm,
                destructive: true,
              );
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
        SecondaryActionButton(icon: Icons.receipt_long_outlined, label: l10n.receiptsScanAnother, onPressed: () => context.pushReplacement('/receipt/capture')),
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
    label: [value, label].join(' '),
    excludeSemantics: true,
    child: Column(
      children: [
        Text(value, style: context.metric),
        Text(label, style: context.text.bodySmall),
      ],
    ),
  );
}

/// Receipts list (history) — reachable from the kitchen.
class ReceiptsListScreen extends ConsumerWidget {
  const ReceiptsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider).value ?? const <PurchaseReceipt>[];
    final l10n = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l10n.receiptsListEyebrow, title: l10n.receiptsListTitle),
      primaryAction: PrimaryActionButton(label: l10n.receiptsCaptureTitle, onPressed: () => context.push('/receipt/capture')),
      children: [
        if (receipts.isEmpty) EmptyState(icon: Icons.receipt_long_outlined, title: l10n.receiptsListEmptyTitle, message: l10n.receiptsListEmptyMessage),
        for (final r in receipts)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(r.merchant ?? l10n.receiptsEyebrow),
              subtitle: Text([formatDay(context, r.createdAt), context.labelOf(r.status), if (r.total != null) _formatMoney(context, r.total!)].join(' · ')),
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

/// Money for display: "$4.99" in English, "4,99 $" in French.
String _formatMoney(BuildContext context, Money m) {
  if (Localizations.localeOf(context).languageCode != 'fr') return m.format();
  final sign = m.minorUnits < 0 ? '-' : '';
  final abs = m.minorUnits.abs();
  return '$sign${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}\u00a0\$';
}

/// Re-export for screens that offer "Tell Chefii".
const showCommandSheet = showKitchenCommandSheet;
