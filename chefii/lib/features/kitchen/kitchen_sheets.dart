import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/voice.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/product_matcher.dart';
import '../../domain/inventory/inventory_command_parser.dart';
import '../../domain/models/inventory.dart';
import '../../domain/units/units.dart';

/// Shows the result of an inventory operation with Undo.
void reportOperation(BuildContext context, WidgetRef ref, OperationResult r) {
  if (r.alreadyApplied) {
    showMessage(context, 'Already done — nothing changed.');
    return;
  }
  final note = r.discrepancies.isEmpty ? '' : ' · ${r.discrepancies.first}';
  showUndoSnack(context, '${r.operation.summary}$note', onUndo: () async {
    try {
      await ref.read(actionsProvider).undo(r.operation.id);
    } catch (e) {
      if (context.mounted) showMessage(context, ErrorState.describe(e), error: true);
    }
  });
}

// ---------------------------------------------------------------- 24 Quick adjust

enum AdjustMode { used, added, discarded, correct }

Future<void> showQuickAdjustSheet(BuildContext context, InventoryLot lot, {AdjustMode initial = AdjustMode.used}) =>
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => QuickAdjustSheet(lot: lot, initial: initial));

class QuickAdjustSheet extends ConsumerStatefulWidget {
  const QuickAdjustSheet({super.key, required this.lot, this.initial = AdjustMode.used});
  final InventoryLot lot;
  final AdjustMode initial;

  @override
  ConsumerState<QuickAdjustSheet> createState() => _QuickAdjustSheetState();
}

class _QuickAdjustSheetState extends ConsumerState<QuickAdjustSheet> {
  late AdjustMode _mode = widget.initial;
  late Quantity _amount = _defaultAmount();
  final _opId = AppActions.newOpId('adj');
  bool _busy = false;

  Quantity _defaultAmount() {
    final u = widget.lot.quantity.unit;
    if (_mode == AdjustMode.correct) return widget.lot.quantity;
    return Quantity(u.dimension == Dimension.count ? 1 : (u == Unit.kg || u == Unit.l ? 0.25 : 100), u);
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final a = ref.read(actionsProvider);
    final lot = widget.lot;
    try {
      final OperationResult r = switch (_mode) {
        AdjustMode.used => await a.useFromLot(lot, _amount, opId: _opId),
        AdjustMode.discarded => await a.useFromLot(lot, _amount, opId: _opId, discard: true),
        AdjustMode.correct => await a.correct({lot.id: _amount}, opId: _opId),
        AdjustMode.added => await a.addManual(
            product: catalogById[lot.productId]?.product ??
                FoodProduct(id: lot.productId, name: lot.productName, category: lot.category, defaultUnit: lot.quantity.unit),
            quantity: _amount,
            opId: _opId,
            locationId: lot.locationId,
          ),
      };
      if (!mounted) return;
      Navigator.pop(context);
      reportOperation(context, ref, r);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lot.productName, style: context.text.headlineSmall),
            Text('Recorded: ${lot.quantity.format()}', style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            SegmentedButton<AdjustMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AdjustMode.used, label: Text('Used')),
                ButtonSegment(value: AdjustMode.added, label: Text('Added')),
                ButtonSegment(value: AdjustMode.discarded, label: Text('Tossed')),
                ButtonSegment(value: AdjustMode.correct, label: Text('Count')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _amount = _defaultAmount();
              }),
            ),
            const SizedBox(height: Space.l),
            Center(
              child: QuantityStepper(
                label: _mode == AdjustMode.correct ? 'Amount you have now' : 'Amount',
                value: _amount,
                min: _mode == AdjustMode.correct ? 0 : 0.001,
                max: _mode == AdjustMode.used || _mode == AdjustMode.discarded ? lot.quantity.amount : null,
                onChanged: (q) => setState(() => _amount = q),
              ),
            ),
            if (_mode == AdjustMode.correct)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Center(child: Text('Counting confirms this item as accurate.', style: context.text.bodySmall)),
              ),
            const SizedBox(height: Space.l),
            PrimaryActionButton(
              label: switch (_mode) {
                AdjustMode.used => 'Use ${_amount.format()}',
                AdjustMode.added => 'Add ${_amount.format()}',
                AdjustMode.discarded => 'Discard ${_amount.format()}',
                AdjustMode.correct => 'Set to ${_amount.format()}',
              },
              loading: _busy,
              onPressed: _amount.isZero && _mode != AdjustMode.correct ? null : _apply,
            ),
            const SizedBox(height: Space.xs),
            SecondaryActionButton(
              label: 'Mark as finished',
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        final r = await ref.read(actionsProvider).markEmpty(lot, opId: '${_opId}_empty');
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        reportOperation(context, ref, r);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Kitchen command ("I used two eggs")

Future<void> showKitchenCommandSheet(BuildContext context, {bool startListening = false}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => KitchenCommandSheet(startListening: startListening),
    );

class KitchenCommandSheet extends ConsumerStatefulWidget {
  const KitchenCommandSheet({super.key, this.startListening = false});
  final bool startListening;

  @override
  ConsumerState<KitchenCommandSheet> createState() => _KitchenCommandSheetState();
}

class _KitchenCommandSheetState extends ConsumerState<KitchenCommandSheet> {
  final _text = TextEditingController();
  InventoryCommand? _parsed;
  Quantity? _quantity;
  bool _listening = false;
  bool _busy = false;
  String? _hint;
  final _opId = AppActions.newOpId('cmd');

  @override
  void initState() {
    super.initState();
    if (widget.startListening) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ProductMatcher _matcher() {
    final household = ref.read(productsProvider).value ?? const <FoodProduct>[];
    final ids = household.map((p) => p.id).toSet();
    return ProductMatcher([...household, ...catalog.map((e) => e.product).where((p) => !ids.contains(p.id))]);
  }

  bool _assumedAmount = false;

  void _parse(String text) {
    final c = InventoryCommandParser(_matcher()).parse(text);
    final needs = c != null &&
        c.product != null &&
        c.quantity == null &&
        (c.action == InventoryCommandAction.add || c.action == InventoryCommandAction.consume || c.action == InventoryCommandAction.setCount);
    setState(() {
      _parsed = c;
      _assumedAmount = needs;
      // A visible, editable starting amount the user must confirm.
      _quantity = needs
          ? Quantity(c.product!.defaultUnit.dimension == Dimension.count ? 1 : 100, c.product!.defaultUnit)
          : c?.quantity;
      _hint = c == null && text.trim().isNotEmpty ? 'Try "I used two eggs" or "add 1 kg flour".' : null;
    });
  }

  Future<void> _listen() async {
    final voice = ref.read(voiceInputProvider);
    if (!await voice.available()) {
      if (mounted) setState(() => _hint = 'Voice isn\'t available. You can type instead — or use your keyboard\'s dictation.');
      return;
    }
    setState(() => _listening = true);
    final words = await voice.listenOnce(onPartial: (p) {
      if (mounted) _text.text = p;
    });
    if (!mounted) return;
    setState(() => _listening = false);
    if (words != null) {
      _text.text = words;
      _parse(words);
    }
  }

  Future<void> _apply() async {
    final c = _parsed;
    if (c == null || c.product == null) return;
    final cmd = InventoryCommand(action: c.action, productQuery: c.productQuery, product: c.product, quantity: _quantity, confidence: c.confidence);
    setState(() => _busy = true);
    try {
      final r = await ref.read(actionsProvider).applyCommand(cmd, opId: _opId);
      if (!mounted) return;
      Navigator.pop(context);
      reportOperation(context, ref, r);
    } on InventoryException catch (e) {
      if (mounted) setState(() => _hint = e.message);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _parsed;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tell Chefii', style: context.text.headlineSmall),
            Text('"I used two eggs" · "we\'re out of milk" · "add 1 kg flour"', style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            TextField(
              controller: _text,
              autofocus: !widget.startListening,
              textInputAction: TextInputAction.done,
              onChanged: _parse,
              onSubmitted: (_) => c?.isActionable == true ? _apply() : null,
              decoration: InputDecoration(
                hintText: 'What happened in the kitchen?',
                suffixIcon: IconButton(
                  tooltip: _listening ? 'Listening' : 'Speak',
                  onPressed: _listening ? () => ref.read(voiceInputProvider).stop() : _listen,
                  icon: Icon(_listening ? Icons.graphic_eq : Icons.mic_none),
                ),
              ),
            ),
            if (_hint != null)
              Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_hint!, style: context.text.bodySmall)),
            if (c != null) ...[
              const SizedBox(height: Space.m),
              Card(
                color: context.palette.surfaceSoft,
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.product == null ? 'We couldn\'t find "${c.productQuery}"' : 'Here\'s what will happen', style: context.text.labelMedium),
                    const SizedBox(height: Space.xxs),
                    Text(
                      c.product == null
                          ? 'Try a simpler name, or add it from the Kitchen tab.'
                          : InventoryCommand(action: c.action, productQuery: c.productQuery, product: c.product, quantity: _quantity).describe(),
                      style: context.text.titleMedium,
                    ),
                    if (_quantity != null) ...[
                      const SizedBox(height: Space.s),
                      if (_assumedAmount) Text('You didn\'t say how much — check the amount:', style: context.text.bodySmall),
                      const SizedBox(height: Space.xs),
                      QuantityStepper(
                        value: _quantity!,
                        min: 0.001,
                        onChanged: (q) => setState(() {
                          _quantity = q;
                          _assumedAmount = false;
                        }),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
            const SizedBox(height: Space.m),
            PrimaryActionButton(
              label: 'Confirm',
              loading: _busy,
              onPressed: c != null && c.product != null && (_quantity != null || c.action == InventoryCommandAction.markEmpty || c.action == InventoryCommandAction.discard)
                  ? _apply
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- storage places

Future<void> showStorageLocationsSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const StorageLocationsSheet(),
    );

/// Add, rename and remove the household's own places ("Garage freezer").
class StorageLocationsSheet extends ConsumerStatefulWidget {
  const StorageLocationsSheet({super.key});

  @override
  ConsumerState<StorageLocationsSheet> createState() => _StorageLocationsSheetState();
}

class _StorageLocationsSheetState extends ConsumerState<StorageLocationsSheet> {
  final _name = TextEditingController();
  StorageKind _kind = StorageKind.pantry;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(String hid) f, {String? done}) async {
    final hid = ref.read(householdIdProvider);
    if (hid == null) return;
    setState(() => _busy = true);
    try {
      await f(hid);
      if (mounted && done != null) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(StorageLocation l) async {
    final controller = TextEditingController(text: l.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename place'),
        content: TextField(controller: controller, autofocus: true, maxLength: 30, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim() == l.name) return;
    await _run((hid) => ref.read(inventoryRepoProvider).renameLocation(hid, l, name));
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(storageLocationsProvider);
    final builtIn = {for (final d in StorageLocation.defaults) d.id};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.l + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Places in your kitchen', style: context.text.headlineSmall),
              Text('Add spots like a garage freezer or a wine fridge.', style: context.text.bodySmall),
              const SizedBox(height: Space.s),
              for (final l in locations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (l.kind) {
                    StorageKind.fridge => Icons.kitchen_outlined,
                    StorageKind.freezer => Icons.ac_unit,
                    StorageKind.pantry => Icons.shelves,
                    StorageKind.custom => Icons.inventory_2_outlined,
                  }),
                  title: Text(l.name),
                  subtitle: Text(builtIn.contains(l.id) ? 'Built in' : 'Kept like a ${l.kind.label.toLowerCase()}'),
                  trailing: builtIn.contains(l.id)
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Rename ${l.name}', onPressed: _busy ? null : () => _rename(l), icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                            tooltip: 'Remove ${l.name}',
                            onPressed: _busy ? null : () => _run((hid) => ref.read(inventoryRepoProvider).removeLocation(hid, l.id), done: 'Removed ${l.name}.'),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ]),
                ),
              const Divider(height: Space.l),
              TextField(
                controller: _name,
                maxLength: 30,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'New place', hintText: 'e.g. Garage freezer'),
                onChanged: (_) => setState(() {}),
              ),
              Text('Kept like a…', style: context.text.labelLarge),
              const SizedBox(height: Space.xxs),
              Wrap(spacing: Space.xs, children: [
                for (final k in [StorageKind.fridge, StorageKind.freezer, StorageKind.pantry])
                  ChoiceChip(label: Text(k.label), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
              ]),
              const SizedBox(height: Space.m),
              PrimaryActionButton(
                label: 'Add place',
                loading: _busy,
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () => _run((hid) async {
                          final added = await ref.read(inventoryRepoProvider).addLocation(hid, name: _name.text, kind: _kind);
                          _name.clear();
                          if (mounted) showMessage(this.context, 'Added ${added.name}.');
                        }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
