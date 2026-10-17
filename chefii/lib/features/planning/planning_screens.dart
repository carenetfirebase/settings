import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/recipe.dart';
import '../../domain/units/units.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../kitchen/kitchen_sheets.dart';
import '../shared/recipe_logic.dart';

CalendarDate weekStartOf(CalendarDate d) => d.addDays(-(d.toLocalDateTime().weekday - 1));

/// "$4.99" in English, "4,99 $" in French.
String _money(BuildContext context, Money m) {
  final tag = localeTag(context);
  if (!tag.startsWith('fr')) return m.format();
  return NumberFormat.currency(locale: tag, symbol: '\$').format(m.minorUnits / 100);
}

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------- 45 Weekly planner

class WeeklyPlannerScreen extends ConsumerStatefulWidget {
  const WeeklyPlannerScreen({super.key});

  @override
  ConsumerState<WeeklyPlannerScreen> createState() => _WeeklyPlannerScreenState();
}

class _WeeklyPlannerScreenState extends ConsumerState<WeeklyPlannerScreen> {
  CalendarDate? _week;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final week = _week ??= weekStartOf(today);
    final entries = ref.watch(mealPlanProvider(week)).value ?? const <MealPlanEntry>[];
    const meals = [MealType.breakfast, MealType.lunch, MealType.dinner, MealType.snack];
    final l = context.l10n;
    final tag = localeTag(context);
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l.planningEyebrow,
        title: l.planningWeekTitle,
        subtitle: [DateFormat.MMMd(tag).format(week.toLocalDateTime()), DateFormat.MMMd(tag).format(week.addDays(6).toLocalDateTime())].join(' – '),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: l.planningPreviousWeek, onPressed: () => setState(() => _week = week.addDays(-7)), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: l.planningNextWeek, onPressed: () => setState(() => _week = week.addDays(7)), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      actions: [IconButton(tooltip: l.planningLeftoversBatch, onPressed: () => context.push('/plan/leftovers'), icon: const Icon(Icons.takeout_dining_outlined))],
      primaryAction: PrimaryActionButton(
        icon: Icons.shopping_bag_outlined,
        label: l.planningBuildShoppingList,
        loading: _busy,
        onPressed: entries.isEmpty
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  final n = await ref.read(planningRepoProvider).addMissingForPlan(
                        householdId: ref.read(householdIdProvider)!,
                        entries: entries,
                        lots: ref.read(lotsProvider).value ?? const [],
                        recipeOf: (e) => ref.read(recipeByIdProvider(e.recipeId)) ?? e.recipeSnapshot,
                      );
                  ref.read(analyticsProvider).log(AnalyticsEvents.shoppingGenerated, {'count': n});
                  if (context.mounted) {
                    showMessage(context, n == 0 ? l.planningHaveEverything : l.planningItemsAdded(n));
                    if (n > 0) context.push('/kitchen/shopping');
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        for (var d = 0; d < 7; d++) ...[
          Builder(builder: (context) {
            final day = week.addDays(d);
            final isToday = day == today;
            return Padding(
              padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
              child: Text(
                isToday ? l.planningDayToday(_capitalized(DateFormat.EEEE(tag).format(day.toLocalDateTime()))) : _capitalized(DateFormat.EEEE(tag).format(day.toLocalDateTime())),
                style: context.text.titleMedium?.copyWith(color: isToday ? context.colors.primary : null),
              ),
            );
          }),
          for (final m in meals)
            Builder(builder: (context) {
              final day = week.addDays(d);
              final e = entries.where((e) => e.date == day && e.mealType == m).toList();
              if (e.isEmpty && m == MealType.snack) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: Space.xs),
                child: ListTile(
                  dense: true,
                  leading: SizedBox(width: 72, child: Text(context.labelOf(m), style: context.text.labelMedium)),
                  title: Text(e.isEmpty ? l.planningAdd : e.map((x) => x.recipeTitle).join(', '),
                      style: e.isEmpty ? context.text.bodyMedium?.copyWith(color: context.palette.muted) : context.text.bodyLarge?.copyWith(decoration: e.every((x) => x.cooked) ? TextDecoration.lineThrough : null)),
                  trailing: e.isEmpty ? const Icon(Icons.add) : PopupMenuButton<String>(
                    tooltip: l.planningOptions,
                    onSelected: (v) {
                      if (v == 'open') context.push('/recipe/${e.first.recipeId}?plan=${e.first.id}');
                      if (v == 'remove') ref.read(planningRepoProvider).removeEntry(e.first.householdId, e.first.id);
                    },
                    itemBuilder: (_) => [PopupMenuItem(value: 'open', child: Text(l.planningOpenRecipe)), PopupMenuItem(value: 'remove', child: Text(l.commonRemove))],
                  ),
                  onTap: () => e.isEmpty ? context.push('/plan/assign?date=${day.toIso()}&meal=${m.name}') : context.push('/recipe/${e.first.recipeId}?plan=${e.first.id}'),
                ),
              );
            }),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 46 Assign meal

class AssignMealScreen extends ConsumerStatefulWidget {
  const AssignMealScreen({super.key, this.recipeId, this.date, this.meal});
  final String? recipeId;
  final String? date;
  final String? meal;

  @override
  ConsumerState<AssignMealScreen> createState() => _AssignMealScreenState();
}

class _AssignMealScreenState extends ConsumerState<AssignMealScreen> {
  late CalendarDate _date = CalendarDate.tryParse(widget.date) ?? ref.read(todayProvider);
  late MealType _meal = widget.meal == null ? MealType.dinner : MealType.values.byName(widget.meal!);
  late String? _recipeId = widget.recipeId;
  int? _portions;
  String _query = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final recipe = _recipeId == null ? null : ref.watch(recipeByIdProvider(_recipeId!));
    final portions = _portions ?? ref.watch(householdProvider).value?.portions ?? 2;
    final options = ref.watch(rankedRecipesProvider((mealType: _meal, maxMinutes: null, tag: null)))
        .where((a) => _query.isEmpty || a.recipe.title.toLowerCase().contains(_query.toLowerCase()))
        .take(8)
        .toList();
    final report = recipe == null ? null : ref.watch(recipeAvailabilityProvider(recipe.scaledTo(portions)));
    final l = context.l10n;
    final tag = localeTag(context);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.planningEyebrow, title: l.planningAddToPlanTitle),
      primaryAction: PrimaryActionButton(
        label: recipe == null ? l.planningChooseRecipe : l.planningPlanMeal(DateFormat.E(tag).format(_date.toLocalDateTime()), context.labelOf(_meal).toLowerCase()),
        loading: _busy,
        onPressed: recipe == null
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await ref.read(planningRepoProvider).assign(
                        householdId: ref.read(householdIdProvider)!,
                        uid: ref.read(uidProvider)!,
                        date: _date,
                        mealType: _meal,
                        recipe: recipe,
                        portions: portions,
                      );
                  ref.read(analyticsProvider).log(AnalyticsEvents.mealPlanned, {'meal_type': _meal.name});
                  if (context.mounted) {
                    context.pop();
                    showMessage(context, l.planningPlanned(recipe.title));
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(DateFormat.yMMMMEEEEd(tag).format(_date.toLocalDateTime())),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date.toLocalDateTime(), firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now().add(const Duration(days: 90)));
              if (d != null) setState(() => _date = CalendarDate.fromDateTime(d));
            },
          ),
        ),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, children: [
          for (final m in MealType.values) ChoiceChip(label: Text(context.labelOf(m)), selected: _meal == m, onSelected: (_) => setState(() => _meal = m)),
        ]),
        const SizedBox(height: Space.m),
        Row(children: [
          Expanded(child: Text(l.planningPortions, style: context.text.titleMedium)),
          QuantityStepper(value: Quantity(portions.toDouble(), Unit.piece), step: 1, min: 1, max: 20, onChanged: (q) => setState(() => _portions = q.amount.round())),
        ]),
        if (recipe != null) ...[
          const SizedBox(height: Space.m),
          LuxuryRecipeCard(recipe: recipe, compact: true, availabilityLabel: report == null ? null : context.availabilityLabel(report), canCookNow: report?.canCookNow ?? false, trailing: IconButton(tooltip: l.planningChangeRecipe, onPressed: () => setState(() => _recipeId = null), icon: const Icon(Icons.close))),
          if (report != null && report.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(l.planningToBuy(report.missing.map((c) => '${c.ingredient.name} (${c.shortBy == null ? '' : context.formatQty(c.shortBy!)})').join(', ')), style: context.text.bodySmall),
            ),
        ] else ...[
          SectionHeader(l.planningChooseRecipe),
          SearchFilterBar(hint: l.planningSearchRecipes, onQuery: (q) => setState(() => _query = q)),
          const SizedBox(height: Space.s),
          for (final a in options)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(a.recipe.title),
                subtitle: Text([formatMinutes(a.recipe.totalMinutes), context.availabilityLabel(a)].join(' · ')),
                onTap: () => setState(() => _recipeId = a.recipe.id),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 47 Batch cooking & leftovers

class LeftoversScreen extends ConsumerWidget {
  const LeftoversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final leftovers = (ref.watch(lotsProvider).value ?? const <InventoryLot>[]).where((l) => l.category == FoodCategory.prepared).toList()
      ..sort((a, b) => (a.daysLeft(today) ?? 99).compareTo(b.daysLeft(today) ?? 99));
    final batch = ref.watch(rankedRecipesProvider((mealType: null, maxMinutes: null, tag: 'batch')));
    final t = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: t.planningEyebrow, title: t.planningLeftoversBatch, subtitle: t.planningLeftoversSubtitle),
      children: [
        SectionHeader(t.planningInYourFridge, topSpacing: 0),
        if (leftovers.isEmpty) Text(t.planningNoLeftovers, style: context.text.bodyMedium),
        for (final l in leftovers)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.productName(l.productId, l.productName), style: context.text.titleMedium),
                Text(
                  [
                    t.planningLeftoverPortions(l.quantity.amount.round()),
                    t.planningMadeOn(formatDay(context, l.acquiredAt)),
                    if (l.daysLeft(today) != null) t.planningEatWithin(l.daysLeft(today)!),
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: Space.xs),
                Wrap(spacing: Space.xs, children: [
                  ActionChip(
                    label: Text(t.planningEatPortion),
                    onPressed: () async {
                      final name = context.productName(l.productId, l.productName);
                      final r = await ref.read(actionsProvider).useFromLot(l, const Quantity(1, Unit.piece), opId: AppActions.newOpId('leftover'));
                      final recipe = l.preparedFromRecipeId == null ? null : ref.read(recipeByIdProvider(l.preparedFromRecipeId!));
                      await ref.read(journalRepoProvider).add(
                            uid: ref.read(uidProvider)!,
                            title: t.planningLeftoversEntryTitle(name),
                            mealType: mealTypeFor(DateTime.now()),
                            eatenAt: DateTime.now(),
                            portions: 1,
                            source: MealEntrySource.leftovers,
                            nutrition: recipe?.nutritionPerServing ?? NutrientProfile.empty,
                            recipeId: recipe?.id,
                          );
                      if (context.mounted) reportOperation(context, ref, r);
                    },
                  ),
                  ActionChip(
                    label: Text(t.planningFreeze),
                    onPressed: () async {
                      final freezer = ref.read(storageLocationsProvider).firstWhere((x) => x.kind == StorageKind.freezer);
                      final r = await ref.read(actionsProvider).move(l, freezer, opId: AppActions.newOpId('freeze'));
                      if (context.mounted) reportOperation(context, ref, r);
                    },
                  ),
                  ActionChip(label: Text(t.planningItemDetails), onPressed: () => context.push('/kitchen/item/${l.id}')),
                ]),
              ]),
            ),
          ),
        SectionHeader(t.planningGoodForBatch),
        for (final a in batch.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: LuxuryRecipeCard(recipe: a.recipe, compact: true, availabilityLabel: context.availabilityLabel(a), canCookNow: a.canCookNow, onTap: () => context.push('/recipe/${a.recipe.id}')),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 48 Smart shopping list

class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final _add = TextEditingController();
  final _opId = AppActions.newOpId('shop');
  bool _busy = false;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final name = _add.text.trim();
    if (name.isEmpty) return;
    final match = catalog.map((e) => e.product).where((p) => p.name.toLowerCase() == name.toLowerCase() || p.aliases.contains(name.toLowerCase())).firstOrNull;
    await ref.read(planningRepoProvider).addShoppingItem(
          householdId: ref.read(householdIdProvider)!,
          name: match?.name ?? name,
          category: match?.category ?? FoodCategory.other,
          productId: match?.id,
        );
    _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider).value ?? const <ShoppingItem>[];
    final checked = items.where((i) => i.checked).toList();
    final byCategory = <FoodCategory, List<ShoppingItem>>{};
    for (final i in items.where((i) => !i.checked)) {
      byCategory.putIfAbsent(i.category, () => []).add(i);
    }
    final cats = byCategory.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.planningKitchenEyebrow, title: l.planningShoppingTitle, subtitle: items.isEmpty ? null : l.planningToBuyCount(items.length - checked.length)),
      primaryAction: checked.isEmpty
          ? null
          : PrimaryActionButton(
              label: l.planningPutAway(checked.length),
              loading: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                try {
                  final r = await ref.read(actionsProvider).addCheckedToKitchen(checked, opId: _opId);
                  if (context.mounted) {
                    if (r == null) {
                      showMessage(context, l.planningAddAmountsFirst);
                    } else {
                      reportOperation(context, ref, r);
                    }
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
            ),
      children: [
        TextField(
          controller: _add,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _addItem(),
          decoration: InputDecoration(hintText: l.planningAddItemHint, suffixIcon: IconButton(tooltip: l.planningAdd, onPressed: _addItem, icon: const Icon(Icons.add))),
        ),
        const SizedBox(height: Space.s),
        // Wraps onto two lines at large text sizes instead of overflowing.
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(onPressed: () => context.push('/plan'), icon: const Icon(Icons.calendar_month_outlined), label: Text(l.planningFromMealPlan)),
          if (checked.isNotEmpty) TextButton(onPressed: () => ref.read(planningRepoProvider).clearChecked(ref.read(householdIdProvider)!, checked), child: Text(l.planningClearChecked)),
        ]),
        if (items.isEmpty) EmptyState(icon: Icons.shopping_bag_outlined, title: l.planningListEmptyTitle, message: l.planningListEmptyMessage),
        for (final c in cats) ...[
          SectionHeader(context.labelOf(c), topSpacing: Space.m),
          for (final i in byCategory[c]!) _ShoppingRow(item: i),
        ],
        if (checked.isNotEmpty) ...[
          SectionHeader(l.planningInBasket, topSpacing: Space.m),
          for (final i in checked) _ShoppingRow(item: i),
          Text(l.planningAfterShopping, style: context.text.bodySmall),
        ],
      ],
    );
  }
}

class _ShoppingRow extends ConsumerWidget {
  const _ShoppingRow({required this.item});
  final ShoppingItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: Space.l), child: const Icon(Icons.delete_outline)),
      onDismissed: (_) => ref.read(planningRepoProvider).removeShoppingItem(item.householdId, item.id),
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: item.checked,
        onChanged: (v) => ref.read(planningRepoProvider).updateShoppingItem(item.copyWith(checked: v)),
        title: Text(item.name, style: TextStyle(decoration: item.checked ? TextDecoration.lineThrough : null)),
        subtitle: Text([
          if (item.quantity != null) context.formatQty(item.quantity!),
          if (item.forRecipeTitles.isNotEmpty) context.l10n.planningForRecipes(item.forRecipeTitles.join(', ')),
          if (item.reason == ShoppingReason.lowStock) context.l10n.planningRunningLow,
        ].join(' · ')),
        secondary: IconButton(tooltip: context.l10n.planningDetails, onPressed: () => context.push('/kitchen/shopping/${item.id}'), icon: const Icon(Icons.chevron_right)),
      ),
    );
  }
}

// ---------------------------------------------------------------- 49 Shopping item details

class ShoppingItemScreen extends ConsumerStatefulWidget {
  const ShoppingItemScreen({super.key, required this.itemId});
  final String itemId;

  @override
  ConsumerState<ShoppingItemScreen> createState() => _ShoppingItemScreenState();
}

class _ShoppingItemScreenState extends ConsumerState<ShoppingItemScreen> {
  ShoppingItem? _i;
  final _preferred = TextEditingController();
  final _note = TextEditingController();
  final _price = TextEditingController();

  @override
  void dispose() {
    _preferred.dispose();
    _note.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingProvider).value;
    final found = items?.where((i) => i.id == widget.itemId).firstOrNull;
    if (_i == null && found != null) {
      _i = found;
      _preferred.text = found.preferredProduct ?? '';
      _note.text = found.note ?? '';
      _price.text = found.estimatedPrice == null ? '' : (found.estimatedPrice!.minorUnits / 100).toStringAsFixed(2);
    }
    final i = _i;
    final l = context.l10n;
    if (i == null) return PremiumAppScaffold(children: [items == null ? const LoadingState() : EmptyState(icon: Icons.shopping_bag_outlined, title: l.planningItemRemovedTitle, message: l.planningItemRemovedMessage)]);
    final alternatives = substitutionAlternatives(i.productId, displayName: context.productName);
    final lastPrice = _lastPaid(ref, i);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: context.labelOf(i.category), title: i.name),
      primaryAction: PrimaryActionButton(
        label: l.commonSave,
        onPressed: () async {
          final cents = (double.tryParse(_price.text.replaceAll(',', '.')) ?? -1) * 100;
          await ref.read(planningRepoProvider).updateShoppingItem(i.copyWith(
                preferredProduct: _preferred.text.trim(),
                note: _note.text.trim(),
                estimatedPrice: cents >= 0 ? Money(cents.round()) : null,
              ));
          if (context.mounted) context.pop();
        },
      ),
      children: [
        Text(l.planningQuantity, style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        QuantityStepper(value: i.quantity ?? const Quantity(1, Unit.piece), min: 0.001, onChanged: (q) => setState(() => _i = i.copyWith(quantity: q))),
        const SizedBox(height: Space.m),
        TextField(controller: _preferred, decoration: InputDecoration(labelText: l.planningPreferredProduct)),
        const SizedBox(height: Space.s),
        TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l.planningExpectedPrice, helperText: lastPrice == null ? null : l.planningLastPaid(_money(context, lastPrice)))),
        const SizedBox(height: Space.s),
        TextField(controller: _note, decoration: InputDecoration(labelText: l.planningNote)),
        if (alternatives.isNotEmpty) ...[
          SectionHeader(l.planningAlternatives),
          Wrap(spacing: Space.xs, children: [for (final a in alternatives) Chip(label: Text(a))]),
        ],
        if (i.forRecipeTitles.isNotEmpty) ...[
          SectionHeader(l.planningNeededFor),
          Text(i.forRecipeTitles.join(', '), style: context.text.bodyMedium),
        ],
      ],
    );
  }

  Money? _lastPaid(WidgetRef ref, ShoppingItem i) {
    final receipts = ref.read(receiptsProvider).value ?? const <PurchaseReceipt>[];
    for (final r in receipts) {
      for (final l in r.lines) {
        if (l.totalPrice != null && (l.matchedProductId == i.productId && i.productId != null || l.name.toLowerCase() == i.name.toLowerCase())) return l.totalPrice;
      }
    }
    return null;
  }
}

List<String> substitutionAlternatives(String? productId, {String Function(String id, String name)? displayName}) {
  if (productId == null) return const [];
  return [
    for (final e in catalog)
      if (e.product.id != productId && e.product.category == catalogById[productId]?.product.category && e.product.allergens.join() == catalogById[productId]?.product.allergens.join())
        displayName?.call(e.product.id, e.product.name) ?? e.product.name,
  ].take(4).toList();
}

// ---------------------------------------------------------------- 52 Spending & waste

class SpendingWasteScreen extends ConsumerWidget {
  const SpendingWasteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = (ref.watch(receiptsProvider).value ?? const <PurchaseReceipt>[]).where((r) => r.status == ReceiptStatus.imported).toList();
    final ops = ref.watch(recentOperationsProvider).value ?? const <InventoryOperation>[];
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final thisMonth = receipts.where((r) => r.createdAt.toLocal().isAfter(monthStart)).toList();
    final spent = thisMonth.fold<int>(0, (s, r) => s + (r.total?.minorUnits ?? r.linesTotal.minorUnits));
    final discards = ops.where((o) => o.kind == OperationKind.discard && !o.isUndone).toList();
    // Waste value estimate: average paid price per receipt line name.
    final byWeek = <int, int>{};
    for (final r in receipts) {
      final week = now.difference(r.createdAt.toLocal()).inDays ~/ 7;
      if (week < 6) byWeek[week] = (byWeek[week] ?? 0) + (r.total?.minorUnits ?? 0);
    }
    final maxWeek = byWeek.values.fold<int>(1, (a, b) => b > a ? b : a);
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.planningKitchenEyebrow, title: l.planningSpendingTitle),
      children: [
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_money(context, Money(spent)), style: context.metric), Text(l.planningGroceriesThisMonth, style: context.text.bodySmall)]))),
          const SizedBox(width: Space.xs),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(discards.length.toString(), style: context.metric), Text(l.planningItemsDiscarded, style: context.text.bodySmall)]))),
        ]),
        SectionHeader(l.planningLastSixWeeks),
        if (byWeek.isEmpty) Text(l.planningScanReceiptsEmpty, style: context.text.bodyMedium),
        for (var w = 5; w >= 0; w--)
          if (byWeek.containsKey(w))
            Semantics(
              label: l.planningWeekAmount(w == 0 ? l.planningThisWeek : l.planningWeeksAgo(w), _money(context, Money(byWeek[w]!))),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(children: [
                  SizedBox(width: 88, child: Text(w == 0 ? l.planningThisWeek : l.planningWeeksAgoShort(w), style: context.text.bodySmall)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: byWeek[w]! / maxWeek, minHeight: 14),
                    ),
                  ),
                  SizedBox(width: 80, child: Text(_money(context, Money(byWeek[w]!)), textAlign: TextAlign.end, style: context.text.bodySmall)),
                ]),
              ),
            ),
        SectionHeader(l.planningRecentlyDiscarded),
        if (discards.isEmpty) Text(l.planningNothingDiscarded, style: context.text.bodyMedium),
        for (final o in discards.take(10)) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline), title: Text(o.summary), subtitle: Text(formatDay(context, o.createdAt))),
        const SizedBox(height: Space.m),
        Text(l.planningSpendingFootnote, style: context.text.bodySmall),
      ],
    );
  }
}
