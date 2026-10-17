import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/actions.dart';
import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/screen_awake.dart';
import '../../core/services/voice.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../../domain/units/units.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../shared/recipe_logic.dart';
import 'timers.dart';

Widget _sessionGate(WidgetRef ref, String id, Widget Function(CookingSession s) builder) {
  final async = ref.watch(cookingSessionProvider(id));
  final s = async.value;
  if (s == null) {
    return Scaffold(
      appBar: AppBar(),
      body: async.isLoading ? const LoadingState() : ErrorState(message: ref.context.l10n.cookingSessionNotFound),
    );
  }
  return builder(s);
}

// ---------------------------------------------------------------- 34 Preparation checklist

class PrepChecklistScreen extends ConsumerStatefulWidget {
  const PrepChecklistScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<PrepChecklistScreen> createState() => _PrepChecklistScreenState();
}

class _PrepChecklistScreenState extends ConsumerState<PrepChecklistScreen> {
  final _gathered = <String>{};

  @override
  Widget build(BuildContext context) {
    return _sessionGate(ref, widget.sessionId, (s) {
      final report = ref.watch(recipeAvailabilityProvider(s.recipe));
      final byName = {for (final c in report.checks) c.ingredient.name: c};
      final items = [...s.recipe.ingredients.map((i) => 'i:${i.name}'), ...s.recipe.equipment.map((e) => 'e:$e')];
      final l = context.l10n;
      return PremiumAppScaffold(
        header: EditorialPageHeader(eyebrow: l.cookingBeforeYouBegin, title: s.recipe.title, subtitle: l.cookingPrepSubtitle(s.servings)),
        primaryAction: PrimaryActionButton(
          icon: Icons.play_arrow_rounded,
          label: _gathered.length >= items.length ? l.cookingBeginCooking : l.cookingBeginAnyway,
          onPressed: () async {
            await ref.read(cookingRepoProvider).update(s.copyWith(status: CookingStatus.cooking));
            if (context.mounted) context.pushReplacement('/cook/${s.id}');
          },
        ),
        children: [
          Text(l.cookingReadyCount(_gathered.length, items.length), style: context.text.bodySmall),
          SectionHeader(l.cookingIngredients, topSpacing: Space.s),
          for (final i in s.recipe.ingredients)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _gathered.contains('i:${i.name}'),
              onChanged: (v) => setState(() => v == true ? _gathered.add('i:${i.name}') : _gathered.remove('i:${i.name}')),
              title: Text(i.display),
              subtitle: switch (byName[i.name]?.availability) {
                IngredientAvailability.partial => Text(l.cookingKitchenShows(byName[i.name]!.onHand == null ? '—' : context.formatQty(byName[i.name]!.onHand!))),
                IngredientAvailability.missing => Text(l.cookingNotInKitchen),
                _ => null,
              },
            ),
          if (s.recipe.equipment.isNotEmpty) ...[
            SectionHeader(l.cookingEquipment),
            for (final e in s.recipe.equipment)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _gathered.contains('e:$e'),
                onChanged: (v) => setState(() => v == true ? _gathered.add('e:$e') : _gathered.remove('e:$e')),
                title: Text(e),
              ),
          ],
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- 35 Guided cooking

class GuidedCookingScreen extends ConsumerStatefulWidget {
  const GuidedCookingScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<GuidedCookingScreen> createState() => _GuidedCookingScreenState();
}

class _GuidedCookingScreenState extends ConsumerState<GuidedCookingScreen> {
  PageController? _pages;
  bool _speak = false;
  Timer? _tick;
  // Kept so dispose() can stop speech without using ref (unsafe there).
  late final Speaker _speaker;

  @override
  void initState() {
    super.initState();
    _speaker = ref.read(speakerProvider);
    _speak = ref.read(settingsProvider).value?.voiceGuidance ?? false;
    ScreenAwake.enable();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.read(cookingTimersProvider).isNotEmpty && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pages?.dispose();
    _speaker.stop();
    ScreenAwake.disable();
    super.dispose();
  }

  void _go(CookingSession s, int step) {
    final n = s.recipe.steps.length;
    final clamped = step.clamp(0, n - 1);
    // Reduce motion: jump (animateToPage rejects a zero duration).
    if (context.reduceMotion) {
      _pages?.jumpToPage(clamped);
    } else {
      _pages?.animateToPage(clamped, duration: Motion.medium, curve: Curves.easeOut);
    }
  }

  void _onPage(CookingSession s, int i) {
    HapticFeedback.selectionClick();
    ref.read(cookingRepoProvider).update(s.copyWith(currentStep: i));
    if (_speak) ref.read(speakerProvider).speak(context.l10n.cookingStepSpeech(i + 1, s.recipe.steps[i].text));
  }

  @override
  Widget build(BuildContext context) {
    return _sessionGate(ref, widget.sessionId, (s) {
      _pages ??= PageController(initialPage: s.currentStep.clamp(0, s.recipe.steps.length - 1));
      final steps = s.recipe.steps;
      final timers = ref.watch(cookingTimersProvider);
      final current = _pages!.hasClients ? (_pages!.page ?? s.currentStep).round() : s.currentStep;
      final last = current >= steps.length - 1;
      final l = context.l10n;
      return Scaffold(
        appBar: AppBar(
          title: Text(s.recipe.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: _speak ? l.cookingStopReadingAloud : l.cookingReadAloud,
              onPressed: () {
                setState(() => _speak = !_speak);
                if (_speak) {
                  ref.read(speakerProvider).speak(l.cookingStepSpeech(current + 1, steps[current].text));
                } else {
                  ref.read(speakerProvider).stop();
                }
              },
              icon: Icon(_speak ? Icons.volume_up : Icons.volume_off_outlined),
            ),
            IconButton(tooltip: l.cookingTimers, onPressed: () => context.push('/cook/timers'), icon: Badge(isLabelVisible: timers.isNotEmpty, label: Text('${timers.length}'), child: const Icon(Icons.timer_outlined))), // l10n-ignore
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Semantics(
                label: l.cookingStepOf(current + 1, steps.length),
                child: LinearProgressIndicator(value: (current + 1) / steps.length, minHeight: 4),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: steps.length,
                onPageChanged: (i) {
                  setState(() {});
                  _onPage(s, i);
                },
                itemBuilder: (context, i) {
                  final st = steps[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.gutter),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.cookingStepOfCaps(i + 1, steps.length), style: context.text.labelSmall?.copyWith(color: context.palette.accent)),
                      const SizedBox(height: Space.m),
                      Semantics(liveRegion: true, child: Text(st.text, style: context.text.headlineMedium?.copyWith(fontFamily: 'Inter', fontWeight: FontWeight.w500, height: 1.35))),
                      if (st.tip != null) ...[
                        const SizedBox(height: Space.l),
                        SoftCard(
                          color: context.palette.accentSoft,
                          child: Row(children: [
                            const Icon(Icons.lightbulb_outline),
                            const SizedBox(width: Space.s),
                            Expanded(child: Text(st.tip!, style: context.text.bodyMedium)),
                          ]),
                        ),
                      ],
                      if (st.timerSeconds != null) ...[
                        const SizedBox(height: Space.l),
                        SecondaryActionButton(
                          icon: Icons.timer_outlined,
                          label: st.timerLabel == null ? l.cookingStartTimer(formatMinutes((st.timerSeconds! / 60).round())) : l.cookingStartNamedTimer(st.timerLabel!, formatMinutes((st.timerSeconds! / 60).round())),
                          onPressed: () {
                            ref.read(cookingTimersProvider.notifier).start(st.timerLabel ?? l.cookingStepTimerLabel(i + 1), Duration(seconds: st.timerSeconds!), l);
                            ref.read(notificationServiceProvider).requestPermission();
                          },
                        ),
                      ],
                    ]),
                  );
                },
              ),
            ),
            if (timers.isNotEmpty) _TimerStrip(timers: timers),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.m),
              child: Row(children: [
                Expanded(child: SecondaryActionButton(label: l.commonBack, icon: Icons.arrow_back, onPressed: current == 0 ? null : () => _go(s, current - 1))),
                const SizedBox(width: Space.s),
                Expanded(
                  flex: 2,
                  child: PrimaryActionButton(
                    label: last ? l.cookingFinishCooking : l.cookingNextStep,
                    icon: last ? Icons.check : Icons.arrow_forward,
                    onPressed: last
                        ? () async {
                            await ref.read(cookingRepoProvider).update(s.copyWith(status: CookingStatus.confirming));
                            if (context.mounted) context.pushReplacement('/cook/${s.id}/confirm');
                          }
                        : () => _go(s, current + 1),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}

class _TimerStrip extends ConsumerWidget {
  const _TimerStrip({required this.timers});
  final List<CookingTimer> timers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        children: [
          for (final t in timers)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: ActionChip(
                avatar: Icon(t.finished(now) ? Icons.notifications_active : (t.running ? Icons.timer : Icons.pause), size: 18),
                label: Text(t.finished(now) ? context.l10n.cookingTimerChipDone(t.label) : '${t.label} ${formatDuration(t.remaining(now))}'),
                onPressed: () => context.push('/cook/timers'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 36 Cooking timers

class CookingTimersScreen extends ConsumerStatefulWidget {
  const CookingTimersScreen({super.key});

  @override
  ConsumerState<CookingTimersScreen> createState() => _CookingTimersScreenState();
}

class _CookingTimersScreenState extends ConsumerState<CookingTimersScreen> {
  Timer? _tick;
  final _label = TextEditingController();
  bool _labelInit = false;
  int _minutes = 5;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_labelInit) {
      _labelInit = true;
      _label.text = context.l10n.cookingDefaultTimerName;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timers = ref.watch(cookingTimersProvider);
    final c = ref.read(cookingTimersProvider.notifier);
    final now = DateTime.now();
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.cookingKitchenEyebrow, title: l.cookingTimers, subtitle: l.cookingTimersSubtitle),
      primaryAction: PrimaryActionButton(
        icon: Icons.add_alarm,
        label: l.cookingStartMinutesTimer(_minutes),
        onPressed: () {
          c.start(_label.text.trim().isEmpty ? l.cookingDefaultTimerName : _label.text.trim(), Duration(minutes: _minutes), l);
          ref.read(notificationServiceProvider).requestPermission();
        },
      ),
      children: [
        if (timers.isEmpty) EmptyState(compact: true, icon: Icons.timer_outlined, title: l.cookingNoTimersTitle, message: l.cookingNoTimersMessage),
        for (final t in timers)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            color: t.finished(now) ? context.palette.accentSoft : null,
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.label, style: context.text.titleMedium),
                    Semantics(
                      liveRegion: t.finished(now),
                      child: Text(t.finished(now) ? l.commonDone : formatDuration(t.remaining(now)), style: context.text.displaySmall?.copyWith(fontFamily: 'Inter', fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
                if (!t.finished(now)) ...[
                  IconButton(tooltip: l.cookingAddMinute, onPressed: () => c.addTime(t.id, const Duration(minutes: 1), l), icon: const Icon(Icons.exposure_plus_1)),
                  IconButton(tooltip: t.running ? l.cookingPause : l.cookingResume, onPressed: () => t.running ? c.pause(t.id) : c.resume(t.id, l), icon: Icon(t.running ? Icons.pause : Icons.play_arrow)),
                ],
                IconButton(tooltip: l.commonRemove, onPressed: () => c.cancel(t.id), icon: const Icon(Icons.close)),
              ]),
            ),
          ),
        SectionHeader(l.cookingNewTimer),
        TextField(controller: _label, decoration: InputDecoration(labelText: l.cookingTimerName, hintText: l.cookingTimerNameHint)),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, children: [
          for (final m in [1, 3, 5, 10, 15, 20, 30, 45])
            ChoiceChip(label: Text(l.cookingMinutesChip(m)), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- 37 Confirm ingredients used

class ConfirmIngredientsScreen extends ConsumerStatefulWidget {
  const ConfirmIngredientsScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<ConfirmIngredientsScreen> createState() => _ConfirmIngredientsScreenState();
}

class _ConfirmIngredientsScreenState extends ConsumerState<ConfirmIngredientsScreen> {
  List<IngredientConsumption>? _items;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _sessionGate(ref, widget.sessionId, (s) {
      final items = _items ??= List.of(s.consumptions);
      final alreadyApplied = s.inventoryOperationId != null && s.status != CookingStatus.cooking;
      final l = context.l10n;
      return PremiumAppScaffold(
        header: EditorialPageHeader(
          eyebrow: l.cookingAlmostDone,
          title: l.cookingWhatDidYouUse,
          subtitle: l.cookingConfirmSubtitle,
        ),
        primaryAction: PrimaryActionButton(
          label: alreadyApplied ? l.commonContinue : l.cookingConfirmAndUpdate,
          loading: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            try {
              final r = await ref.read(actionsProvider).confirmCooking(s, items);
              if (!context.mounted) return;
              if (r.discrepancies.isNotEmpty) {
                showMessage(context, context.l10n.cookingDiscrepancies(r.discrepancies.length));
              }
              context.pushReplacement('/cook/${s.id}/done');
            } catch (e) {
              if (context.mounted) showMessage(context, ErrorState.describeIn(context, e), error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
        children: [
          if (items.isEmpty) Text(l.cookingNothingTracked, style: context.text.bodyMedium),
          for (var i = 0; i < items.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        items[i].substitutedWithName ?? items[i].ingredientName,
                        style: context.text.titleMedium?.copyWith(decoration: items[i].skipped ? TextDecoration.lineThrough : null),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => items[i] = items[i].copyWith(skipped: !items[i].skipped)),
                      child: Text(items[i].skipped ? l.cookingInclude : l.cookingDidntUse),
                    ),
                  ]),
                  if (!items[i].skipped && items[i].planned != null)
                    Row(children: [
                      Text(l.cookingRecipeAmount(context.formatQty(items[i].planned!)), style: context.text.bodySmall),
                      const Spacer(),
                      QuantityStepper(
                        label: l.cookingAmountUsed(items[i].ingredientName),
                        value: items[i].actual ?? items[i].planned!,
                        min: 0,
                        onChanged: (q) => setState(() => items[i] = items[i].copyWith(actual: q)),
                      ),
                    ]),
                ]),
              ),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- 38 Meal complete

class MealCompleteScreen extends ConsumerStatefulWidget {
  const MealCompleteScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<MealCompleteScreen> createState() => _MealCompleteScreenState();
}

class _MealCompleteScreenState extends ConsumerState<MealCompleteScreen> {
  double _eaten = 1;
  int? _leftovers;
  int _rating = 0;
  MealType? _meal;
  bool _favourite = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _sessionGate(ref, widget.sessionId, (s) {
      final household = ref.watch(householdProvider).value;
      final eaters = (household?.portions ?? 1).clamp(1, s.servings);
      final leftovers = _leftovers ??= (s.servings - eaters).clamp(0, s.servings);
      final meal = _meal ??= s.recipe.mealTypes.contains(mealTypeFor(DateTime.now())) ? mealTypeFor(DateTime.now()) : s.recipe.mealTypes.first;
      final wellness = ref.watch(wellnessProvider).value;
      final n = s.recipe.nutritionPerServing.scale(_eaten);
      final l = context.l10n;
      final eatenAmount = _eaten == _eaten.roundToDouble() ? '${_eaten.round()}' : (Localizations.localeOf(context).languageCode == 'fr' ? '$_eaten'.replaceAll('.', ',') : '$_eaten');
      return PremiumAppScaffold(
        showBack: false,
        header: EditorialPageHeader(eyebrow: l.cookingBonAppetit, title: s.recipe.title, subtitle: l.cookingKitchenUpdated),
        primaryAction: PrimaryActionButton(
          label: l.cookingFinish,
          loading: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            try {
              await ref.read(actionsProvider).completeCooking(s, portionsEaten: _eaten, leftoverPortions: leftovers, rating: _rating == 0 ? null : _rating, mealType: meal);
              if (_favourite) await ref.read(profileRepoProvider).setFavourite(ref.read(uidProvider)!, s.recipe.id, true);
              if (!context.mounted) return;
              context.go('/today');
              showMessage(context, leftovers > 0 ? l.cookingLoggedWithLeftovers(leftovers) : l.cookingLoggedToJournal);
            } catch (e) {
              if (context.mounted) showMessage(context, ErrorState.describeIn(context, e), error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
        children: [
          Text(l.cookingHowWasIt, style: context.text.titleMedium),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: l.cookingStars(i),
                onPressed: () => setState(() => _rating = i),
                icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: context.palette.accent, size: 32),
              ),
          ]),
          SectionHeader(l.cookingYourPortion),
          Row(children: [
            Expanded(child: Text(l.cookingPortionsYouAte, style: context.text.bodyLarge)),
            QuantityStepper(value: Quantity(_eaten, Unit.piece), step: 0.5, min: 0, max: s.servings.toDouble(), onChanged: (q) => setState(() => _eaten = q.amount)),
          ]),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.xs, children: [
            for (final m in MealType.values) ChoiceChip(label: Text(context.labelOf(m)), selected: meal == m, onSelected: (_) => setState(() => _meal = m)),
          ]),
          if ((wellness?.showNutritionOnRecipes ?? true) && _eaten > 0) ...[
            const SizedBox(height: Space.m),
            NutritionSummaryCard(nutrition: n, title: l.cookingYourMeal, subtitle: l.cookingPortionCount(_eaten, eatenAmount), showCalories: wellness?.calorieTracking ?? false),
          ],
          SectionHeader(l.cookingLeftovers),
          Row(children: [
            Expanded(child: Text(l.cookingPortionsToSave, style: context.text.bodyLarge)),
            QuantityStepper(value: Quantity(leftovers.toDouble(), Unit.piece), step: 1, min: 0, max: 20, onChanged: (q) => setState(() => _leftovers = q.amount.round())),
          ]),
          if (leftovers > 0) Text(l.cookingLeftoversReminder, style: context.text.bodySmall),
          const SizedBox(height: Space.m),
          ToggleTile(title: l.cookingSaveFavourite, value: _favourite, onChanged: (v) => setState(() => _favourite = v), icon: Icons.favorite_border),
        ],
      );
    });
  }
}

/// Nutrition label for a profile (used by journal & dashboards).
String kcalLabel(NutrientProfile n) => '${n[Nutrient.energyKcal].round()} kcal';
