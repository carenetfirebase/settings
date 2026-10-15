import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../data/repositories/kitchen_repositories.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/inventory.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/recipe.dart';
import '../kitchen/kitchen_sheets.dart';
import '../shared/recipe_logic.dart';

/// Default local meal times when the user hasn't set reminders.
const defaultMealTimes = {
  MealType.breakfast: '08:00',
  MealType.lunch: '12:30',
  MealType.snack: '15:30',
  MealType.dinner: '18:30',
};

DateTime mealTimeOn(CalendarDate d, MealType m, Map<String, String> custom) {
  final hhmm = custom[m.name] ?? defaultMealTimes[m]!;
  final p = hhmm.split(':').map(int.parse).toList();
  return DateTime(d.year, d.month, d.day, p[0], p[1]);
}

// ---------------------------------------------------------------- 09 Today

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int? _minutes;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final profile = ref.watch(profileProvider).value;
    final today = ref.watch(todayProvider);
    final lots = ref.watch(lotsProvider).value ?? const <InventoryLot>[];
    final routine = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final plan = ref.watch(mealPlanProvider(today)).value ?? const <MealPlanEntry>[];
    final receipts = ref.watch(receiptsProvider).value ?? const <PurchaseReceipt>[];
    final notifications = ref.watch(notificationsProvider).value ?? const <AppNotification>[];
    final isDemo = ref.watch(appConfigProvider).isDemo;
    final meal = mealTypeFor(now);
    final minutes = _minutes ?? profile?.culinary.weeknightMinutes ?? 30;
    final ranked = ref.watch(rankedRecipesProvider((mealType: meal, maxMinutes: minutes, tag: null)));
    final plannedNow = plan.where((e) => e.date == today && e.mealType == meal && !e.cooked).firstOrNull;
    final featured = plannedNow != null ? ref.watch(recipeByIdProvider(plannedNow.recipeId)) ?? plannedNow.recipeSnapshot : ranked.firstOrNull?.recipe;
    final featuredReport = featured == null ? null : ranked.where((r) => r.recipe.id == featured.id).firstOrNull;

    final dueSoon = lots.where((l) => (l.daysLeft(today) ?? 99) <= 2).toList();
    final toVerify = lots.where((l) => l.statusOn(today) == InventoryStatus.needsReview).length;
    final inProgress = receipts.where((r) => !r.status.isTerminal).toList();
    final lowStock = PlanningRepository.lowStock(lots, ref.watch(productsProvider).value ?? const []);
    final unread = notifications.where((n) => !n.read).length;

    return PremiumAppScaffold(
      showBack: false,
      actions: [
        IconButton(
          tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
          onPressed: () => context.push('/today/notifications'),
          icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none)),
        ),
      ],
      header: EditorialPageHeader(
        eyebrow: DateFormat('EEEE, MMMM d').format(now),
        title: '${greetingFor(now)}${profile == null ? '' : ',\n${profile.firstName}'}.',
      ),
      primaryAction: featured == null
          ? PrimaryActionButton(icon: Icons.receipt_long_outlined, label: 'Scan a receipt', onPressed: () => context.push('/receipt/capture'))
          : PrimaryActionButton(icon: Icons.restaurant, label: 'Start cooking', onPressed: () => context.push('/recipe/${featured.id}')),
      children: [
        if (isDemo) const DemoBanner(),
        for (final r in inProgress)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: SoftCard(
              color: context.palette.infoSoft,
              onTap: () => context.push(r.status == ReceiptStatus.needsReview ? '/receipt/${r.id}/review' : '/receipt/${r.id}/processing'),
              child: Row(children: [
                Icon(r.status == ReceiptStatus.needsReview ? Icons.rate_review_outlined : Icons.hourglass_top, color: context.palette.info),
                const SizedBox(width: Space.s),
                Expanded(child: Text(r.status == ReceiptStatus.needsReview ? 'Your receipt is ready to review' : 'Reading your receipt…', style: context.text.titleSmall)),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        Text(plannedNow != null ? 'PLANNED FOR ${meal.label.toUpperCase()}' : 'FOR ${meal.label.toUpperCase()}', style: context.text.labelSmall),
        const SizedBox(height: Space.xs),
        Wrap(spacing: Space.xs, children: [
          for (final m in [15, 30, 45, 60])
            ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => setState(() => _minutes = m)),
        ]),
        const SizedBox(height: Space.s),
        if (featured != null)
          LuxuryRecipeCard(
            recipe: featured,
            availabilityLabel: featuredReport?.label,
            canCookNow: featuredReport?.canCookNow ?? false,
            rationale: featuredReport?.usesExpiringItems == true ? 'Uses ingredients that need eating soon.' : null,
            onTap: () => context.push('/recipe/${featured.id}'),
          )
        else
          EmptyState(
            compact: true,
            icon: Icons.restaurant_menu,
            title: 'Nothing fits in $minutes minutes',
            message: 'Try more time, or ask your chef for an idea.',
            actionLabel: 'Ask the chef',
            onAction: () => context.push('/chef'),
          ),
        const SizedBox(height: Space.xs),
        Row(children: [
          TextButton.icon(onPressed: () => context.push('/chef'), icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Ask the chef')),
          const Spacer(),
          TextButton(onPressed: () => context.push('/today/briefing'), child: const Text('Daily briefing')),
        ]),
        const SizedBox(height: Space.s),
        MorningRoutineCard(
          routine: routine,
          breakfastTitle: routine.tomorrowRecipeId == null ? null : ref.watch(recipeByIdProvider(routine.tomorrowRecipeId!))?.title,
          onTap: () => context.push(routine.enabled ? '/morning/evening' : '/morning/setup'),
        ),
        const SectionHeader('Your kitchen'),
        Row(children: [
          Expanded(child: _QuickTile(icon: Icons.inventory_2_outlined, value: '${lots.length}', label: 'items', onTap: () => context.go('/kitchen'))),
          const SizedBox(width: Space.xs),
          Expanded(child: _QuickTile(icon: Icons.schedule, value: '${dueSoon.length}', label: 'use soon', onTap: () => context.push('/kitchen/freshness'))),
          const SizedBox(width: Space.xs),
          Expanded(child: _QuickTile(icon: Icons.fact_check_outlined, value: '$toVerify', label: 'to verify', onTap: () => context.push('/kitchen/reconcile'))),
        ]),
        const SizedBox(height: Space.s),
        Row(children: [
          Expanded(
            child: SecondaryActionButton(icon: Icons.receipt_long_outlined, label: 'Scan', onPressed: () => context.push('/receipt/capture')),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: SecondaryActionButton(icon: Icons.mic_none, label: 'I used…', onPressed: () => showKitchenCommandSheet(context)),
          ),
        ]),
        if (dueSoon.isNotEmpty || lowStock.isNotEmpty) ...[
          const SectionHeader('Reminders'),
          for (final l in dueSoon.take(3))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.eco_outlined),
              title: Text('Use ${l.productName} soon'),
              subtitle: Text(l.daysLeftIsEstimate ? 'Estimated from purchase date' : 'Recorded date ${l.useByDate!.toIso()}'),
              onTap: () => context.push('/kitchen/item/${l.id}'),
            ),
          for (final p in lowStock.take(3))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shopping_basket_outlined),
              title: Text('Running low on ${p.name}'),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(planningRepoProvider).addShoppingItem(householdId: ref.read(householdIdProvider)!, name: p.name, category: p.category, productId: p.id, quantity: p.lowStockThreshold, reason: ShoppingReason.lowStock);
                  if (context.mounted) showMessage(context, '${p.name} added to your shopping list');
                },
                child: const Text('Add to list'),
              ),
            ),
        ],
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.value, required this.label, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
        onTap: onTap,
        semanticLabel: '$value $label',
        padding: const EdgeInsets.all(Space.s),
        child: Row(children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: context.text.titleLarge),
              Text(label, style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- 10 Daily briefing

class DailyBriefingScreen extends ConsumerWidget {
  const DailyBriefingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final plan = (ref.watch(mealPlanProvider(today)).value ?? const <MealPlanEntry>[]).where((e) => e.date == today).toList();
    final settings = ref.watch(settingsProvider).value;
    final routine = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final lots = ref.watch(lotsProvider).value ?? const <InventoryLot>[];
    final custom = settings?.mealReminders ?? const <String, String>{};
    plan.sort((a, b) => a.mealType.index.compareTo(b.mealType.index));
    final dueSoon = lots.where((l) => (l.daysLeft(today) ?? 99) <= 1).toList();

    final prep = <(DateTime, String)>[];
    for (final e in plan) {
      final r = ref.watch(recipeByIdProvider(e.recipeId)) ?? e.recipeSnapshot;
      if (r == null || e.cooked) continue;
      final at = mealTimeOn(today, e.mealType, custom);
      prep.add((at.subtract(Duration(minutes: r.totalMinutes)), 'Start ${r.title} (${formatMinutes(r.totalMinutes)})'));
    }
    prep.sort((a, b) => a.$1.compareTo(b.$1));

    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: DateFormat('EEEE').format(DateTime.now()), title: 'Your day in food'),
      primaryAction: plan.isEmpty ? PrimaryActionButton(label: 'Plan today\'s meals', onPressed: () => context.push('/plan')) : null,
      children: [
        const SectionHeader('Meals', topSpacing: 0),
        if (plan.isEmpty) Text('Nothing planned yet — Today will suggest something at each meal.', style: context.text.bodyMedium),
        for (var i = 0; i < plan.length; i++)
          MealTimelineItem(
            time: mealTimeOn(today, plan[i].mealType, custom),
            title: plan[i].recipeTitle,
            mealType: plan[i].mealType,
            subtitle: '${plan[i].portions} portion${plan[i].portions == 1 ? '' : 's'}',
            done: plan[i].cooked,
            isLast: i == plan.length - 1,
            onTap: () => context.push('/recipe/${plan[i].recipeId}'),
          ),
        if (prep.isNotEmpty) ...[
          const SectionHeader('Preparation'),
          for (final (t, label) in prep)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.timer_outlined), title: Text(label), subtitle: Text('around ${formatTime(context, t)}')),
        ],
        const SectionHeader('Kitchen alerts'),
        if (dueSoon.isEmpty) Text('Nothing urgent.', style: context.text.bodyMedium),
        for (final l in dueSoon)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.eco_outlined), title: Text(l.productName), subtitle: Text('${l.quantity.format()} · use today if you can'), onTap: () => context.push('/kitchen/item/${l.id}')),
        const SectionHeader('Tomorrow morning'),
        MorningRoutineCard(routine: routine, onTap: () => context.push(routine.enabled ? '/morning/evening' : '/morning/setup')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 11 Notification centre

class NotificationCentreScreen extends ConsumerWidget {
  const NotificationCentreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).value ?? const <AppNotification>[];
    final uid = ref.watch(uidProvider);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Today', title: 'Notifications'),
      actions: [
        if (items.any((n) => !n.read))
          TextButton(
            onPressed: uid == null ? null : () => ref.read(profileRepoProvider).markAllNotificationsRead(uid, items.where((n) => !n.read).map((n) => n.id)),
            child: const Text('Mark all read'),
          ),
      ],
      children: [
        if (items.isEmpty)
          const EmptyState(icon: Icons.notifications_none, title: 'You\'re all caught up', message: 'Receipt results, sharing invitations and reviews will appear here.'),
        for (final n in items)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            color: n.read ? null : context.palette.surfaceSoft,
            child: ListTile(
              leading: Icon(switch (n.kind) {
                NotificationKind.receipt => Icons.receipt_long_outlined,
                NotificationKind.mealReminder => Icons.restaurant,
                NotificationKind.inventory => Icons.kitchen_outlined,
                NotificationKind.sharing => Icons.group_outlined,
                NotificationKind.review => Icons.rate_review_outlined,
                NotificationKind.routine => Icons.alarm,
                NotificationKind.system => Icons.info_outline,
              }),
              title: Text(n.title, style: n.read ? null : context.text.titleSmall),
              subtitle: Text('${n.body}\n${formatDay(n.createdAt)}'),
              isThreeLine: true,
              onTap: () {
                if (uid != null) ref.read(profileRepoProvider).markNotificationRead(uid, n.id);
                if (n.route != null) context.push(n.route!);
              },
            ),
          ),
      ],
    );
  }
}
