import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../data/ai/ai_gateway.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/catalog/product_matcher.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/units/units.dart';
import '../shared/ai_consent.dart';
import '../shared/photo_picker.dart';
import 'kitchen_sheets.dart';

String locationName(WidgetRef ref, String id) =>
    ref.read(storageLocationsProvider).where((l) => l.id == id).firstOrNull?.name ?? id;

// ---------------------------------------------------------------- 21 My Kitchen

class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  String _query = '';
  String? _category;
  String _location = 'all';

  @override
  Widget build(BuildContext context) {
    final lotsAsync = ref.watch(lotsProvider);
    final lots = lotsAsync.value ?? const <InventoryLot>[];
    final today = ref.watch(todayProvider);
    final locations = ref.watch(storageLocationsProvider);
    final needsReview = lots.where((l) {
      final s = l.statusOn(today);
      return s == InventoryStatus.needsReview || s == InventoryStatus.estimated;
    }).length;
    final dueSoon = lots.where((l) => (l.daysLeft(today) ?? 99) <= 2).length;
    final categories = {for (final l in lots) l.category.label}.toList()..sort();

    final filtered = lots.where((l) {
      if (_location != 'all' && l.locationId != _location) return false;
      if (_category != null && l.category.label != _category) return false;
      if (_query.isNotEmpty && !l.productName.toLowerCase().contains(_query.toLowerCase())) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));

    return PremiumAppScaffold(
      showBack: false,
      actions: [
        IconButton(tooltip: 'Shopping list', onPressed: () => context.push('/kitchen/shopping'), icon: const Icon(Icons.shopping_bag_outlined)),
        IconButton(tooltip: 'Tell Chefii', onPressed: () => showKitchenCommandSheet(context), icon: const Icon(Icons.mic_none)),
      ],
      header: EditorialPageHeader(
        eyebrow: 'Kitchen',
        title: 'My kitchen',
        subtitle: lots.isEmpty ? null : '${lots.length} item${lots.length == 1 ? '' : 's'} across ${locations.length} places',
      ),
      primaryAction: PrimaryActionButton(icon: Icons.receipt_long_outlined, label: 'Scan a receipt', onPressed: () => context.push('/receipt/capture')),
      children: [
        if (lotsAsync.isLoading && lots.isEmpty) const LoadingState(message: 'Opening your kitchen…'),
        if (lotsAsync.hasError && lots.isEmpty)
          ErrorState(message: ErrorState.describe(lotsAsync.error!), onRetry: () => ref.invalidate(lotsProvider)),
        if (!lotsAsync.isLoading && lots.isEmpty && !lotsAsync.hasError)
          EmptyState(
            icon: Icons.kitchen_outlined,
            title: 'Your kitchen is empty',
            message: 'Scan a grocery receipt and Chefii fills it in for you — or add a few things by hand.',
            actionLabel: 'Add an item',
            onAction: () => context.push('/kitchen/add'),
            secondaryLabel: 'Scan the fridge instead',
            onSecondary: () => context.push('/kitchen/scan'),
          ),
        if (lots.isNotEmpty) ...[
          Row(children: [
            Expanded(
              child: _StatTile(
                icon: Icons.schedule,
                value: '$dueSoon',
                label: 'Use soon',
                onTap: () => context.push('/kitchen/freshness'),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: _StatTile(
                icon: Icons.fact_check_outlined,
                value: '$needsReview',
                label: 'To verify',
                onTap: () => context.push('/kitchen/reconcile'),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: _StatTile(icon: Icons.add_circle_outline, value: 'Add', label: 'an item', onTap: () => context.push('/kitchen/add')),
            ),
          ]),
          const SizedBox(height: Space.m),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: 'all', label: Text('All')),
                for (final l in locations) ButtonSegment(value: l.id, label: Text(l.name)),
              ],
              selected: {_location},
              onSelectionChanged: (s) => setState(() => _location = s.first),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showStorageLocationsSheet(context),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Manage places'),
            ),
          ),
          const SizedBox(height: Space.m),
          SearchFilterBar(
            hint: 'Search your kitchen',
            onQuery: (q) => setState(() => _query = q),
            filters: categories,
            selected: _category,
            onFilter: (c) => setState(() => _category = c),
          ),
          const SizedBox(height: Space.m),
          if (filtered.isEmpty)
            const EmptyState(icon: Icons.search_off, title: 'Nothing matches', message: 'Try a different search or filter.', compact: true),
          for (final l in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: IngredientCard(
                lot: l,
                today: today,
                locationName: _location == 'all' ? locationName(ref, l.locationId) : null,
                onTap: () => context.push('/kitchen/item/${l.id}'),
                onQuickUse: () => showQuickAdjustSheet(context, l),
              ),
            ),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
            ActionChip(avatar: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Scan fridge'), onPressed: () => context.push('/kitchen/scan')),
            ActionChip(avatar: const Icon(Icons.bar_chart, size: 18), label: const Text('Spending & waste'), onPressed: () => context.push('/kitchen/spending')),
            ActionChip(avatar: const Icon(Icons.receipt_outlined, size: 18), label: const Text('Receipts'), onPressed: () => context.push('/kitchen/receipts')),
          ]),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        semanticLabel: '$label: $value',
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(height: Space.xs),
          Text(value, style: context.metric),
          Text(label, style: context.text.bodySmall),
        ]),
      );
}

// ---------------------------------------------------------------- 22 Storage location

class StorageLocationScreen extends ConsumerWidget {
  const StorageLocationScreen({super.key, required this.locationId});
  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lots = (ref.watch(lotsProvider).value ?? const <InventoryLot>[]).where((l) => l.locationId == locationId).toList();
    final today = ref.watch(todayProvider);
    lots.sort((a, b) => (a.daysLeft(today) ?? 999).compareTo(b.daysLeft(today) ?? 999));
    final confident = lots.where((l) => l.statusOn(today) == InventoryStatus.confirmed).length;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Storage',
        title: locationName(ref, locationId),
        subtitle: lots.isEmpty ? null : '$confident of ${lots.length} confirmed · soonest first',
      ),
      primaryAction: lots.isEmpty
          ? null
          : SecondaryActionButton(icon: Icons.fact_check_outlined, label: 'Verify these items', onPressed: () => context.push('/kitchen/reconcile?location=$locationId')),
      children: [
        if (lots.isEmpty)
          EmptyState(icon: Icons.inventory_2_outlined, title: 'Nothing here yet', message: 'Items you add to ${locationName(ref, locationId).toLowerCase()} appear here.', actionLabel: 'Add an item', onAction: () => context.push('/kitchen/add?location=$locationId')),
        for (final l in lots)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: IngredientCard(lot: l, today: today, onTap: () => context.push('/kitchen/item/${l.id}'), onQuickUse: () => showQuickAdjustSheet(context, l)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 23 Ingredient details

class IngredientDetailScreen extends ConsumerWidget {
  const IngredientDetailScreen({super.key, required this.lotId});
  final String lotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lotAsync = ref.watch(lotProvider(lotId));
    final lot = lotAsync.value;
    if (lot == null) {
      return PremiumAppScaffold(children: [
        lotAsync.isLoading
            ? const LoadingState()
            : const EmptyState(icon: Icons.inventory_2_outlined, title: 'Item not found', message: 'It may have been removed by someone in your household.'),
      ]);
    }
    final today = ref.watch(todayProvider);
    final history = ref.watch(productHistoryProvider(lot.productId)).value ?? const <InventoryAdjustment>[];
    final ref100 = nutrientReferences[lot.productId];
    final status = lot.statusOn(today);
    final days = lot.daysLeft(today);

    Widget row(String label, String value, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(children: [
            Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: context.text.bodyMedium)),
            ?trailing,
          ]),
        );

    return PremiumAppScaffold(
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) async {
            final actions = ref.read(actionsProvider);
            if (v == 'discard') {
              final ok = await showConfirmActionSheet(context,
                  title: 'Discard ${lot.productName}?', message: 'Records the remaining ${lot.quantity.format()} as food waste.', confirmLabel: 'Discard', destructive: true);
              if (!ok || !context.mounted) return;
              final r = await actions.markEmpty(lot, opId: AppActions.newOpId('discard'), discarded: true);
              if (context.mounted) reportOperation(context, ref, r);
            } else {
              final to = ref.read(storageLocationsProvider).firstWhere((l) => l.id == v);
              final r = await actions.move(lot, to, opId: AppActions.newOpId('move'));
              if (context.mounted) reportOperation(context, ref, r);
            }
          },
          itemBuilder: (_) => [
            for (final l in ref.read(storageLocationsProvider).where((l) => l.id != lot.locationId))
              PopupMenuItem(value: l.id, child: Text('Move to ${l.name}')),
            const PopupMenuItem(value: 'discard', child: Text('Discard')),
          ],
        ),
      ],
      header: EditorialPageHeader(
        eyebrow: lot.category.label,
        title: lot.productName,
        subtitle: '${lot.quantity.format()} · ${locationName(ref, lot.locationId)}',
        trailing: InventoryStatusBadge(status: status),
      ),
      primaryAction: PrimaryActionButton(label: 'Update amount', onPressed: () => showQuickAdjustSheet(context, lot)),
      children: [
        SoftCard(
          child: Column(children: [
            row('Recorded amount', lot.quantity.format()),
            row('Originally', lot.initialQuantity.format()),
            row('Added', formatDay(context, lot.acquiredAt)),
            row('Source', switch (lot.source) {
              LotSource.receipt => 'Receipt${lot.provenance.raw == null ? '' : ' · "${lot.provenance.raw}"'}',
              LotSource.scan => 'Photo scan',
              LotSource.barcode => 'Barcode',
              LotSource.leftover => 'Leftovers you saved',
              LotSource.demo => 'Example ingredient',
              _ => 'Added by hand',
            }),
            if (lot.packageDescription != null) row('Package', lot.packageDescription!),
            row(
              lot.useByDate != null ? 'Date on package' : 'Estimated quality',
              lot.useByDate?.toIso() ?? (lot.estimatedBestBefore == null ? 'Unknown' : '~${lot.estimatedBestBefore!.toIso()}'),
              trailing: IconButton(
                tooltip: 'Set date from package',
                icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: (lot.useByDate ?? today).toLocalDateTime(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    helpText: 'Date printed on the package',
                  );
                  if (picked == null) return;
                  final hid = ref.read(householdIdProvider)!;
                  await ref.read(docStoreProvider).set('households/$hid/lots/${lot.id}', {'useByDate': CalendarDate.fromDateTime(picked).toIso()}, merge: true);
                },
              ),
            ),
          ]),
        ),
        if (days != null && days <= 2)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Card(
              color: context.palette.warningSoft,
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Text(
                  lot.daysLeftIsEstimate
                      ? 'Our estimate suggests using this soon. Estimates are a guide only — check how it looks and smells, and follow the package date.'
                      : 'The date you recorded is ${days < 0 ? 'past' : 'close'}. Follow the package guidance; when in doubt, throw it out.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.ink),
                ),
              ),
            ),
          ),
        if (status != InventoryStatus.confirmed && !lot.isDepleted) ...[
          const SizedBox(height: Space.s),
          SecondaryActionButton(
            icon: Icons.check,
            label: 'This amount is right',
            onPressed: () async {
              final r = await ref.read(actionsProvider).correct({lot.id: lot.quantity}, opId: AppActions.newOpId('verify'));
              if (context.mounted) reportOperation(context, ref, r);
            },
          ),
        ],
        if (ref100 != null) ...[
          const SectionHeader('Nutrition reference'),
          NutritionSummaryCard(nutrition: ref100.per100g, subtitle: 'per 100 g · ${ref100.source}'),
        ],
        const SectionHeader('Activity'),
        if (history.isEmpty) Text('No activity yet.', style: context.text.bodySmall),
        for (final a in history.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (a.type) {
              AdjustmentType.intake => Icons.add_circle_outline,
              AdjustmentType.consume => Icons.restaurant,
              AdjustmentType.discard => Icons.delete_outline,
              AdjustmentType.correction => Icons.tune,
              AdjustmentType.reversal => Icons.undo,
              _ => Icons.swap_horiz,
            }),
            title: Text('${a.type.label} ${a.delta.isZero ? '' : a.delta.format().replaceFirst('-', '')}'),
            subtitle: Text('${formatDay(context, a.createdAt)} · ${formatTime(context, a.createdAt)}${a.reason == null ? '' : ' · ${a.reason}'}'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 25 Add product

class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.initialLocation});
  final String? initialLocation;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _search = TextEditingController();
  FoodProduct? _product;
  Quantity? _qty;
  String? _location;
  CalendarDate? _useBy;
  String? _barcode;
  bool _busy = false;
  final _opId = AppActions.newOpId('add');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<FoodProduct> _allProducts() {
    final household = ref.read(productsProvider).value ?? const <FoodProduct>[];
    final ids = household.map((p) => p.id).toSet();
    return [...household, ...catalog.map((e) => e.product).where((p) => !ids.contains(p.id))];
  }

  void _select(FoodProduct p) => setState(() {
        _product = p;
        _qty = Quantity(p.defaultUnit.dimension == Dimension.count ? 1 : (p.defaultUnit == Unit.g || p.defaultUnit == Unit.ml ? 500 : 1), p.defaultUnit);
        _location ??= widget.initialLocation ?? p.defaultStorage.name;
      });

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _BarcodeScannerPage()));
    if (code == null || !mounted) return;
    final known = _allProducts().where((p) => p.barcode == code).firstOrNull;
    setState(() => _barcode = code);
    if (known != null) {
      _select(known);
    } else {
      showMessage(context, 'New barcode — tell us what it is once and we\'ll remember it.');
    }
  }

  Future<void> _save() async {
    var p = _product;
    final name = _search.text.trim();
    if (p == null && name.isNotEmpty) {
      p = FoodProduct(
        id: 'p_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
        name: name[0].toUpperCase() + name.substring(1),
        category: FoodCategory.other,
        defaultUnit: _qty?.unit ?? Unit.piece,
      );
    }
    if (p == null || _qty == null) return;
    if (_barcode != null && p.barcode != _barcode) {
      p = FoodProduct(
        id: p.id, name: p.name, category: p.category, defaultUnit: p.defaultUnit, brand: p.brand, barcode: _barcode,
        aliases: p.aliases, bridge: p.bridge, defaultStorage: p.defaultStorage, typicalShelfLifeDays: p.typicalShelfLifeDays,
        nutrientRefId: p.nutrientRefId, allergens: p.allergens, lowStockThreshold: p.lowStockThreshold,
      );
      await ref.read(inventoryRepoProvider).saveProduct(ref.read(householdIdProvider)!, p);
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(actionsProvider).addManual(
            product: p,
            quantity: _qty!,
            opId: _opId,
            locationId: _location,
            useBy: _useBy,
            source: _barcode != null ? LotSource.barcode : LotSource.manual,
          );
      if (!mounted) return;
      context.pop();
      reportOperation(context, ref, r);
    } catch (e) {
      if (mounted) showMessage(context, ErrorState.describe(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _product != null || _search.text.trim().isEmpty
        ? const <ProductMatch>[]
        : ProductMatcher(_allProducts()).search(_search.text, limit: 6, minScore: 0.3);
    final locations = ref.watch(storageLocationsProvider);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Kitchen', title: 'Add an item'),
      primaryAction: PrimaryActionButton(
        label: _product == null && _search.text.trim().isEmpty ? 'Choose an item' : 'Add to kitchen',
        loading: _busy,
        onPressed: (_product != null || _search.text.trim().isNotEmpty) && _qty != null ? _save : null,
      ),
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'What are you adding?',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _product == null ? null : IconButton(tooltip: 'Change', icon: const Icon(Icons.close), onPressed: () => setState(() => _product = null)),
              ),
              onChanged: (_) => setState(() {
                _product = null;
                _qty ??= const Quantity(1, Unit.piece);
              }),
            ),
          ),
          const SizedBox(width: Space.xs),
          IconButton.filledTonal(tooltip: 'Scan barcode', onPressed: _scanBarcode, icon: const Icon(Icons.qr_code_scanner)),
        ]),
        if (_barcode != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('Barcode $_barcode', style: context.text.bodySmall)),
        for (final m in matches)
          ListTile(
            leading: Icon(categoryIcon(m.product.category)),
            title: Text(m.product.name),
            subtitle: Text(m.product.category.label),
            onTap: () {
              _search.text = m.product.name;
              _select(m.product);
            },
          ),
        if (_product == null && _search.text.trim().isNotEmpty && matches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text('We\'ll add "${_search.text.trim()}" as a new item.', style: context.text.bodySmall),
          ),
        if (_qty != null) ...[
          const SectionHeader('How much?'),
          Row(children: [
            QuantityStepper(value: _qty!, min: 0.001, onChanged: (q) => setState(() => _qty = q)),
            const SizedBox(width: Space.s),
            DropdownButton<Unit>(
              value: _qty!.unit,
              items: [for (final u in Unit.values) DropdownMenuItem(value: u, child: Text(u.symbol))],
              onChanged: (u) => setState(() => _qty = Quantity(_qty!.amount, u!)),
            ),
          ]),
          const SectionHeader('Where does it live?'),
          Wrap(spacing: Space.xs, children: [
            for (final l in locations)
              ChoiceChip(label: Text(l.name), selected: (_location ?? 'pantry') == l.id, onSelected: (_) => setState(() => _location = l.id)),
          ]),
          const SectionHeader('Date on the package'),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined),
            label: Text(_useBy == null ? 'Add a best-before or use-by date (optional)' : _useBy!.toIso()),
            onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 1500)));
              if (d != null) setState(() => _useBy = CalendarDate.fromDateTime(d));
            },
          ),
        ],
      ],
    );
  }
}

class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a barcode')),
      body: PhotoCaptureOverlay(
        hint: 'Point at the barcode on the package',
        aspectRatio: 1.6,
        child: MobileScanner(
          onDetect: (capture) {
            final v = capture.barcodes.firstOrNull?.rawValue;
            if (v == null || _done) return;
            _done = true;
            Navigator.of(context).pop(v);
          },
          errorBuilder: (context, error) => PermissionDeniedState(
            permission: 'Camera',
            why: 'Chefii needs the camera to read barcodes. You can still type the item name.',
            onAlternative: () => Navigator.of(context).pop(),
            alternativeLabel: 'Type it instead',
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 26 Fridge / pantry scan

class FridgeScanScreen extends ConsumerStatefulWidget {
  const FridgeScanScreen({super.key});

  @override
  ConsumerState<FridgeScanScreen> createState() => _FridgeScanScreenState();
}

class _FridgeScanScreenState extends ConsumerState<FridgeScanScreen> {
  StorageKind _where = StorageKind.fridge;
  ScanResult? _result;
  final _accepted = <int>{};
  final _amounts = <int, Quantity>{};
  bool _busy = false;
  bool _denied = false;
  final _opId = AppActions.newOpId('scan');

  Future<void> _capture(bool camera) async {
    if (!await ensureAiConsent(context, ref, feature: 'scanning your shelves')) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _denied = false;
    });
    try {
      final photo = await pickPhoto(camera: camera, maxWidth: 1600);
      if (photo == null) return;
      final r = await ref.read(aiGatewayProvider).scanStorage(householdId: ref.read(householdIdProvider)!, image: photo.bytes, location: _where);
      setState(() {
        _result = r;
        _accepted.clear();
        _amounts.clear();
        for (var i = 0; i < r.suggestions.length; i++) {
          final s = r.suggestions[i];
          if (s.visibleCount != null) _amounts[i] = s.visibleCount!;
        }
      });
    } on PhotoPermissionDenied {
      setState(() => _denied = true);
    } on AiUnavailableException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addConfirmed() async {
    final r = _result!;
    final inputs = <(ScanSuggestion, Quantity)>[];
    for (final i in _accepted) {
      final q = _amounts[i];
      if (q == null) return showMessage(context, 'Enter an amount for ${r.suggestions[i].name}.', error: true);
      inputs.add((r.suggestions[i], q));
    }
    setState(() => _busy = true);
    try {
      final hid = ref.read(householdIdProvider)!;
      final loc = ref.read(storageLocationsProvider).firstWhere((l) => l.kind == _where).id;
      final result = await ref.read(inventoryRepoProvider).addLots(
            householdId: hid,
            operationId: _opId,
            actorUid: ref.read(uidProvider)!,
            kind: OperationKind.scanImport,
            summary: 'Added ${inputs.length} item${inputs.length == 1 ? '' : 's'} from a photo',
            inputs: [
              for (final (s, q) in inputs)
                NewLotInput(
                  product: (s.productId == null ? null : catalogById[s.productId]?.product) ??
                      FoodProduct(id: 'p_${s.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}', name: s.name, category: s.category, defaultUnit: q.unit),
                  quantity: q,
                  locationId: loc,
                  source: LotSource.scan,
                  // The user confirmed the item and typed the amount.
                  provenance: Provenance(source: r.isDemo ? ProvenanceSource.demo : ProvenanceSource.scanAi, confidence: 0.95),
                ),
            ],
          );
      if (!mounted) return;
      context.pop();
      reportOperation(context, ref, result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return PremiumAppScaffold(
      header: const EditorialPageHeader(
        eyebrow: 'Kitchen',
        title: 'Scan your shelves',
        subtitle: 'We\'ll suggest what we can see. Nothing is added until you confirm it.',
      ),
      primaryAction: r == null
          ? PrimaryActionButton(icon: Icons.photo_camera_outlined, label: 'Take a photo', loading: _busy, onPressed: () => _capture(true))
          : PrimaryActionButton(
              label: _accepted.isEmpty ? 'Select items to add' : 'Add ${_accepted.length} item${_accepted.length == 1 ? '' : 's'}',
              loading: _busy,
              onPressed: _accepted.isEmpty ? null : _addConfirmed,
            ),
      children: [
        if (_denied)
          PermissionDeniedState(
            permission: 'Camera',
            why: 'Allow camera access in Settings to scan, or choose a photo from your library.',
            alternativeLabel: 'Choose from library',
            onAlternative: () => _capture(false),
          ),
        if (r == null) ...[
          SegmentedButton<StorageKind>(
            segments: const [
              ButtonSegment(value: StorageKind.fridge, label: Text('Fridge')),
              ButtonSegment(value: StorageKind.freezer, label: Text('Freezer')),
              ButtonSegment(value: StorageKind.pantry, label: Text('Pantry')),
            ],
            selected: {_where},
            onSelectionChanged: (s) => setState(() => _where = s.first),
          ),
          const SizedBox(height: Space.l),
          const FoodArtwork(artKey: 'herb', height: 200, label: 'Open fridge'),
          const SizedBox(height: Space.m),
          Text('Tips: open the door fully, use good light, and take one photo per shelf for best results.', style: context.text.bodySmall),
          TextButton.icon(onPressed: _busy ? null : () => _capture(false), icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose from library')),
        ],
        if (r != null) ...[
          if (r.isDemo) const DemoBanner(message: 'Demo: sample suggestions — your photo was not analysed.'),
          if (r.message != null) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Text(r.message!, style: context.text.bodySmall)),
          if (r.suggestions.isEmpty)
            const EmptyState(icon: Icons.visibility_off_outlined, title: 'We couldn\'t spot anything', message: 'Try a brighter, closer photo of one shelf.', compact: true),
          for (var i = 0; i < r.suggestions.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _accepted.contains(i),
                    onChanged: (v) => setState(() => v == true ? _accepted.add(i) : _accepted.remove(i)),
                    title: Text(r.suggestions[i].name),
                    subtitle: Text([
                      '${(r.suggestions[i].confidence * 100).round()}% sure',
                      ?r.suggestions[i].note,
                    ].join(' · ')),
                  ),
                  if (_accepted.contains(i))
                    Row(children: [
                      Text('Amount', style: context.text.bodySmall),
                      const SizedBox(width: Space.s),
                      if (_amounts[i] == null)
                        TextButton(onPressed: () => setState(() => _amounts[i] = const Quantity(1, Unit.piece)), child: const Text('Enter amount'))
                      else
                        QuantityStepper(value: _amounts[i]!, min: 0.001, onChanged: (q) => setState(() => _amounts[i] = q)),
                    ]),
                ]),
              ),
            ),
          TextButton(onPressed: () => setState(() => _result = null), child: const Text('Take another photo')),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 27 Freshness centre

class FreshnessCentreScreen extends ConsumerWidget {
  const FreshnessCentreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final lots = (ref.watch(lotsProvider).value ?? const <InventoryLot>[]).where((l) => (l.daysLeft(today) ?? 99) <= 3).toList()
      ..sort((a, b) => a.daysLeft(today)!.compareTo(b.daysLeft(today)!));
    final freezer = ref.watch(storageLocationsProvider).firstWhere((l) => l.kind == StorageKind.freezer);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Kitchen', title: 'Use soon', subtitle: 'Things worth cooking, freezing or deciding on.'),
      primaryAction: lots.isEmpty ? null : PrimaryActionButton(icon: Icons.restaurant_menu, label: 'Find recipes that use these', onPressed: () => context.push('/discover?filter=expiring')),
      children: [
        if (lots.isEmpty)
          const EmptyState(icon: Icons.eco_outlined, title: 'Nothing needs attention', message: 'We\'ll let you know when something should be used soon.'),
        for (final l in lots)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(l.productName, style: context.text.titleMedium)),
                  InventoryStatusBadge(status: l.statusOn(today)),
                ]),
                Text(
                  '${l.quantity.format()} · ${() {
                    final d = l.daysLeft(today)!;
                    final est = l.daysLeftIsEstimate ? ' (estimate)' : '';
                    return d < 0
                        ? 'date passed ${-d} day${d == -1 ? '' : 's'} ago$est'
                        : d == 0
                            ? 'date is today$est'
                            : '$d day${d == 1 ? '' : 's'} left$est';
                  }()}',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.s),
                Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
                  ActionChip(
                    avatar: const Icon(Icons.restaurant, size: 18),
                    label: const Text('Cook with this'),
                    onPressed: () => context.push('/discover?ingredient=${l.productId}'),
                  ),
                  if (l.locationId != freezer.id)
                    ActionChip(
                      avatar: const Icon(Icons.ac_unit, size: 18),
                      label: const Text('Freeze'),
                      onPressed: () async {
                        final r = await ref.read(actionsProvider).move(l, freezer, opId: AppActions.newOpId('freeze'));
                        if (context.mounted) reportOperation(context, ref, r);
                      },
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Discard'),
                    onPressed: () async {
                      final r = await ref.read(actionsProvider).markEmpty(l, opId: AppActions.newOpId('discard'), discarded: true);
                      if (context.mounted) reportOperation(context, ref, r);
                    },
                  ),
                ]),
              ]),
            ),
          ),
        const SectionHeader('Food safety'),
        SoftCard(
          color: context.palette.infoSoft,
          child: Text(
            'Chefii\'s dates are estimates from typical storage times, not safety guarantees. Follow "use by" and "best before" dates on packages, '
            'keep your fridge at 4 °C (40 °F) or below, and when in doubt, throw it out. For guidance, see Health Canada\'s food safety pages.',
            style: context.text.bodySmall?.copyWith(color: context.palette.ink),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 28 Reconciliation

class ReconciliationScreen extends ConsumerStatefulWidget {
  const ReconciliationScreen({super.key, this.locationId});
  final String? locationId;

  @override
  ConsumerState<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends ConsumerState<ReconciliationScreen> {
  final _counts = <String, Quantity>{};
  final _opId = AppActions.newOpId('reconcile');
  bool _busy = false;
  ({int changed, int verified})? _summary;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final lots = (ref.watch(lotsProvider).value ?? const <InventoryLot>[]).where((l) {
      if (widget.locationId != null) return l.locationId == widget.locationId;
      final s = l.statusOn(today);
      return s == InventoryStatus.needsReview || s == InventoryStatus.estimated || s == InventoryStatus.pastRecordedDate;
    }).toList();

    if (_summary != null) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(eyebrow: 'Kitchen', title: 'All squared away'),
        primaryAction: PrimaryActionButton(label: 'Back to kitchen', onPressed: () => context.pop()),
        children: [
          EmptyState(
            icon: Icons.task_alt,
            title: '${_summary!.verified} item${_summary!.verified == 1 ? '' : 's'} verified',
            message: _summary!.changed == 0 ? 'Every amount was already right.' : '${_summary!.changed} amount${_summary!.changed == 1 ? ' was' : 's were'} corrected. You can undo from the kitchen.',
          ),
        ],
      );
    }

    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Kitchen',
        title: 'Quick check',
        subtitle: lots.isEmpty ? null : 'Adjust anything that\'s off, then confirm. ${lots.length} item${lots.length == 1 ? '' : 's'}.',
      ),
      primaryAction: lots.isEmpty
          ? null
          : PrimaryActionButton(
              label: 'Confirm all',
              loading: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                try {
                  final counts = {for (final l in lots) l.id: _counts[l.id] ?? l.quantity};
                  final changed = lots.where((l) => _counts[l.id] != null && _counts[l.id] != l.quantity).length;
                  await ref.read(actionsProvider).correct(counts, opId: _opId);
                  setState(() => _summary = (changed: changed, verified: counts.length));
                } catch (e) {
                  if (context.mounted) showMessage(context, ErrorState.describe(e), error: true);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
            ),
      children: [
        if (lots.isEmpty)
          const EmptyState(icon: Icons.verified_outlined, title: 'Everything looks accurate', message: 'Nothing needs checking right now.'),
        for (final l in lots)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: Space.xs, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(l.productName, style: context.text.titleMedium),
                  InventoryStatusBadge(status: l.statusOn(today)),
                ]),
                const SizedBox(height: Space.xs),
                Wrap(spacing: Space.s, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  QuantityStepper(value: _counts[l.id] ?? l.quantity, onChanged: (q) => setState(() => _counts[l.id] = q), label: l.productName),
                  if (_counts[l.id] != null && _counts[l.id] != l.quantity)
                    Text('was ${l.quantity.format()}', style: context.text.bodySmall),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Small helper for nutrients in detail rows.
String kcalPer100(String productId) {
  final r = nutrientReferences[productId];
  return r == null ? '—' : '${r.per100g[Nutrient.energyKcal].round()} kcal / 100 g';
}
