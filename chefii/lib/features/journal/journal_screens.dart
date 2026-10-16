import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/voice.dart';
import '../../data/ai/ai_gateway.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/recipe.dart';
import '../../domain/units/units.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../shared/ai_consent.dart';
import '../shared/photo_picker.dart';
import '../shared/recipe_logic.dart';
import '../today/today_screens.dart';

({DateTime from, DateTime to}) dayRange(DateTime localDay) {
  final start = DateTime(localDay.year, localDay.month, localDay.day);
  return (from: start.toUtc(), to: start.add(const Duration(days: 1)).toUtc());
}

({DateTime from, DateTime to}) lastDays(int n) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: n - 1));
  return (from: start.toUtc(), to: DateTime(now.year, now.month, now.day + 1).toUtc());
}

NutrientProfile sumNutrition(Iterable<MealConsumption> meals) {
  var total = const NutrientProfile({}, completeness: 1);
  var any = false;
  for (final m in meals) {
    total = any ? total + m.nutrition : m.nutrition;
    any = true;
  }
  return any ? total : NutrientProfile.empty;
}

// ---------------------------------------------------------------- 54 Meal journal timeline (Journal tab)

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider(dayRange(_day)));
    final meals = [...async.value ?? const <MealConsumption>[]]..sort((a, b) => a.eatenAt.compareTo(b.eatenAt));
    final wellness = ref.watch(wellnessProvider).value ?? const WellnessPreferences();
    final isToday = DateUtils.isSameDay(_day, DateTime.now());
    final total = sumNutrition(meals);
    final l = context.l10n;
    return PremiumAppScaffold(
      showBack: false,
      actions: [
        IconButton(tooltip: l.journalNutritionTooltip, onPressed: () => context.push('/you/nutrition'), icon: const Icon(Icons.insights_outlined)),
        PopupMenuButton<String>(
          tooltip: l.journalMoreTooltip,
          onSelected: (v) => context.push(v),
          itemBuilder: (_) => [
            PopupMenuItem(value: '/journal/history', child: Text(l.journalFullHistory)),
            PopupMenuItem(value: '/journal/patterns', child: Text(l.journalEatingPatterns)),
            PopupMenuItem(value: '/journal/reminders', child: Text(l.journalMealReminders)),
          ],
        ),
      ],
      header: EditorialPageHeader(
        eyebrow: l.journalEyebrow,
        title: formatDay(context, _day),
        subtitle: DateFormat.yMMMMd(localeTag(context)).format(_day),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: l.journalPreviousDay, onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: l.journalNextDay, onPressed: isToday ? null : () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      primaryAction: PrimaryActionButton(icon: Icons.add, label: l.journalLogAMeal, onPressed: () => context.push('/journal/add?day=${_day.toIso8601String().substring(0, 10)}')),
      children: [
        if (async.isLoading && meals.isEmpty) const LoadingState(),
        if (!async.isLoading && meals.isEmpty)
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: isToday ? l.journalEmptyTodayTitle : l.journalEmptyTitle,
            message: l.journalEmptyMessage,
          ),
        for (var i = 0; i < meals.length; i++)
          MealTimelineItem(
            time: meals[i].eatenAt,
            title: meals[i].title,
            mealType: meals[i].mealType,
            subtitle: [
              l.journalPortionCount(meals[i].portions, _fmtPortions(context, meals[i].portions)),
              if (wellness.calorieTracking && meals[i].nutrition.has(Nutrient.energyKcal)) '≈ ${meals[i].nutrition[Nutrient.energyKcal].round()} kcal',
            ].join(' · '),
            isLast: i == meals.length - 1,
            onTap: () => context.push('/journal/entry/${meals[i].id}'),
          ),
        if (meals.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.replay),
              label: Text(l.journalRepeatMeal(meals.last.title)),
              onPressed: () async {
                final m = meals.last;
                await ref.read(journalRepoProvider).add(
                      uid: ref.read(uidProvider)!,
                      title: m.title,
                      mealType: mealTypeFor(DateTime.now()),
                      eatenAt: DateTime.now(),
                      portions: m.portions,
                      source: MealEntrySource.repeat,
                      nutrition: m.nutrition,
                      recipeId: m.recipeId,
                    );
                if (context.mounted) {
                  setState(() => _day = DateTime.now());
                  showMessage(context, l.journalLoggedAgain(m.title));
                }
              },
            ),
          ),
          if (wellness.showNutritionOnRecipes) ...[
            SectionHeader(l.journalDaySoFar),
            NutritionSummaryCard(nutrition: total, title: l.journalEstimatedIntake, subtitle: l.journalMealCount(meals.length), showCalories: wellness.calorieTracking),
          ],
        ],
      ],
    );
  }
}

String _fmtPortions(BuildContext context, double p) {
  final s = p == p.roundToDouble() ? p.round().toString() : p.toString();
  return Localizations.localeOf(context).languageCode == 'fr' ? s.replaceAll('.', ',') : s;
}

// ---------------------------------------------------------------- 51 Food journal (history & corrections)

class FoodJournalScreen extends ConsumerWidget {
  const FoodJournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(journalProvider(lastDays(30))).value ?? const <MealConsumption>[];
    final byDay = <String, List<MealConsumption>>{};
    for (final m in meals) {
      byDay.putIfAbsent(DateFormat('yyyy-MM-dd').format(m.eatenAt.toLocal()), () => []).add(m);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.journalEyebrow, title: l.journalHistoryTitle, subtitle: l.journalHistorySubtitle),
      children: [
        if (meals.isEmpty) EmptyState(icon: Icons.history, title: l.journalHistoryEmptyTitle, message: l.journalHistoryEmptyMessage),
        for (final d in days) ...[
          SectionHeader(formatDay(context, DateTime.parse(d)), topSpacing: Space.m),
          for (final m in byDay[d]!)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(m.title),
                subtitle: Text([context.labelOf(m.mealType), formatTime(context, m.eatenAt), l.journalPortionCount(m.portions, _fmtPortions(context, m.portions))].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => context.push('/journal/entry/${m.id}'),
              ),
            ),
        ],
      ],
    );
  }
}

class JournalEntryScreen extends ConsumerStatefulWidget {
  const JournalEntryScreen({super.key, required this.entryId});
  final String entryId;

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  MealConsumption? _m;
  double? _origPortions;

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(journalProvider(lastDays(120))).value;
    final found = meals?.where((m) => m.id == widget.entryId).firstOrNull;
    if (_m == null && found != null) {
      _m = found;
      _origPortions = found.portions;
    }
    final m = _m;
    final l = context.l10n;
    if (m == null) return PremiumAppScaffold(children: [meals == null ? const LoadingState() : EmptyState(icon: Icons.menu_book_outlined, title: l.journalEntryNotFoundTitle, message: l.journalEntryNotFoundMessage)]);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: context.labelOf(m.mealType), title: m.title),
      actions: [
        IconButton(
          tooltip: l.journalDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showConfirmActionSheet(context, title: l.journalDeleteTitle, message: l.journalDeleteMessage, confirmLabel: l.journalDelete, destructive: true);
            if (!ok) return;
            await ref.read(journalRepoProvider).delete(m.uid, m.id);
            if (context.mounted) context.pop();
          },
        ),
      ],
      primaryAction: PrimaryActionButton(
        label: l.journalSaveChanges,
        onPressed: () async {
          // Nutrition scales with the corrected portion size.
          final scale = (_origPortions ?? m.portions) == 0 ? 1.0 : m.portions / _origPortions!;
          await ref.read(journalRepoProvider).update(m.copyWith(nutrition: found!.nutrition.scale(scale)));
          if (context.mounted) context.pop();
        },
      ),
      children: [
        Wrap(spacing: Space.xs, children: [
          for (final t in MealType.values) ChoiceChip(label: Text(context.labelOf(t)), selected: m.mealType == t, onSelected: (_) => setState(() => _m = m.copyWith(mealType: t))),
        ]),
        const SizedBox(height: Space.m),
        Card(
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l.journalDayAtTime(formatDay(context, m.eatenAt), formatTime(context, m.eatenAt))),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final local = m.eatenAt.toLocal();
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(local));
              if (t != null) setState(() => _m = m.copyWith(eatenAt: DateTime(local.year, local.month, local.day, t.hour, t.minute).toUtc()));
            },
          ),
        ),
        const SizedBox(height: Space.m),
        Row(children: [
          Expanded(child: Text(l.journalPortions, style: context.text.titleMedium)),
          QuantityStepper(value: Quantity(m.portions, Unit.piece), step: 0.5, min: 0.5, onChanged: (q) => setState(() => _m = m.copyWith(portions: q.amount))),
        ]),
        if (m.nutrition.completeness > 0) ...[
          const SizedBox(height: Space.m),
          NutritionSummaryCard(
            nutrition: found!.nutrition.scale(m.portions / (_origPortions ?? m.portions)),
            title: l.journalEstimated,
            subtitle: l.journalForPortions(m.portions, _fmtPortions(context, m.portions)),
            showCalories: ref.watch(wellnessProvider).value?.calorieTracking ?? false,
          ),
        ],
        if (m.recipeId != null) TextButton(onPressed: () => context.push('/recipe/${m.recipeId}'), child: Text(l.journalViewRecipe)),
      ],
    );
  }
}

// ---------------------------------------------------------------- 55 Quick meal entry

class QuickMealEntryScreen extends ConsumerStatefulWidget {
  const QuickMealEntryScreen({super.key, this.day});
  final String? day;

  @override
  ConsumerState<QuickMealEntryScreen> createState() => _QuickMealEntryScreenState();
}

class _QuickMealEntryScreenState extends ConsumerState<QuickMealEntryScreen> {
  final _text = TextEditingController();
  MealEstimate? _estimate;
  Recipe? _recipe;
  Uint8List? _photo;
  double _portions = 1;
  late MealType _meal = mealTypeFor(DateTime.now());
  late DateTime _at = _initialTime();
  bool _busy = false;
  bool _listening = false;

  DateTime _initialTime() {
    final now = DateTime.now();
    final d = widget.day == null ? null : DateTime.tryParse(widget.day!);
    if (d == null || DateUtils.isSameDay(d, now)) return now;
    return mealTimeOn(CalendarDate.fromDateTime(d), _meal, const {});
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _estimateNow() async {
    if (_text.text.trim().isEmpty && _photo == null) return;
    if (!await ensureAiConsent(context, ref, feature: context.l10n.journalAiFeatureEstimatingMeals)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final e = await ref.read(aiGatewayProvider).estimateMeal(description: _text.text.trim(), photo: _photo);
      setState(() {
        _estimate = e;
        _recipe = null;
      });
    } on AiUnavailableException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final title = _recipe?.title ?? _estimate?.title ?? _text.text.trim();
    if (title.isEmpty) return;
    final nutrition = (_recipe?.nutritionPerServing ?? _estimate?.nutrition ?? NutrientProfile.empty).scale(_portions);
    setState(() => _busy = true);
    try {
      await ref.read(journalRepoProvider).add(
            uid: ref.read(uidProvider)!,
            title: title,
            mealType: _meal,
            eatenAt: _at,
            portions: _portions,
            source: _recipe != null ? MealEntrySource.recipe : (_photo != null ? MealEntrySource.photo : MealEntrySource.quickEntry),
            nutrition: nutrition,
            recipeId: _recipe?.id,
          );
      ref.read(analyticsProvider).log(AnalyticsEvents.mealLogged, {'meal_type': _meal.name, 'source': _recipe != null ? 'recipe' : 'quick'});
      if (mounted) {
        context.pop();
        showMessage(context, context.l10n.journalMealLogged(title));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(allRecipesProvider);
    final q = _text.text.trim().toLowerCase();
    final matches = q.length < 2 ? const <Recipe>[] : recipes.where((r) => r.title.toLowerCase().contains(q)).take(4).toList();
    final ready = _recipe != null || _estimate != null || q.isNotEmpty;
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.journalEyebrow, title: l.journalQuickTitle),
      primaryAction: PrimaryActionButton(label: l.journalLogMeal, loading: _busy, onPressed: ready ? _save : null),
      children: [
        TextField(
          controller: _text,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {
            _estimate = null;
            _recipe = null;
          }),
          onSubmitted: (_) => _estimateNow(),
          decoration: InputDecoration(
            hintText: l.journalQuickHint,
            suffixIcon: IconButton(
              tooltip: _listening ? l.journalListening : l.journalSpeak,
              icon: Icon(_listening ? Icons.graphic_eq : Icons.mic_none),
              onPressed: () async {
                final voice = ref.read(voiceInputProvider);
                if (!await voice.available()) {
                  if (context.mounted) showMessage(context, l.journalVoiceUnavailable);
                  return;
                }
                setState(() => _listening = true);
                final words = await voice.listenOnce(onPartial: (p) => _text.text = p);
                if (!mounted) return;
                setState(() => _listening = false);
                if (words != null) {
                  _text.text = words;
                  await _estimateNow();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, children: [
          ActionChip(
            avatar: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_photo == null ? l.journalAddPhoto : l.journalPhotoAdded),
            onPressed: () async {
              try {
                final p = await pickPhoto(camera: true, maxWidth: 1400);
                if (p != null) setState(() => _photo = p.bytes);
              } on PhotoPermissionDenied {
                if (context.mounted) showMessage(context, l.journalCameraOff, error: true);
              }
            },
          ),
          ActionChip(avatar: const Icon(Icons.calculate_outlined, size: 18), label: Text(l.journalEstimateNutrition), onPressed: _busy ? null : _estimateNow),
        ]),
        for (final r in matches)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(r.title),
            subtitle: Text(l.journalSavedRecipe),
            selected: _recipe?.id == r.id,
            onTap: () => setState(() {
              _recipe = r;
              _estimate = null;
              _text.text = r.title;
            }),
          ),
        if (_estimate != null) ...[
          const SizedBox(height: Space.m),
          if (_estimate!.isDemo) DemoBanner(message: l.journalDemoEstimate),
          NutritionSummaryCard(nutrition: _estimate!.nutrition.scale(_portions), title: _estimate!.title, subtitle: _estimate!.note ?? l.journalForPortions(_portions, _fmtPortions(context, _portions)), showCalories: ref.watch(wellnessProvider).value?.calorieTracking ?? false),
        ],
        SectionHeader(l.journalDetails),
        Wrap(spacing: Space.xs, children: [
          for (final t in MealType.values) ChoiceChip(label: Text(context.labelOf(t)), selected: _meal == t, onSelected: (_) => setState(() => _meal = t)),
        ]),
        const SizedBox(height: Space.s),
        Row(children: [
          Expanded(child: Text(l.journalPortions, style: context.text.titleMedium)),
          QuantityStepper(value: Quantity(_portions, Unit.piece), step: 0.5, min: 0.5, onChanged: (q) => setState(() => _portions = q.amount)),
        ]),
        Card(
          margin: const EdgeInsets.only(top: Space.s),
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l.journalDayAtTime(formatDay(context, _at), formatTime(context, _at))),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
              if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 56 Eating reminders

class EatingRemindersScreen extends ConsumerStatefulWidget {
  const EatingRemindersScreen({super.key});

  @override
  ConsumerState<EatingRemindersScreen> createState() => _EatingRemindersScreenState();
}

class _EatingRemindersScreenState extends ConsumerState<EatingRemindersScreen> {
  AppSettings? _s;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = _s ??= ref.watch(settingsProvider).value;
    if (s == null) return const Scaffold(body: LoadingState());
    String two(int v) => v.toString().padLeft(2, '0');
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.journalEyebrow, title: l.journalMealReminders, subtitle: l.journalRemindersSubtitle),
      primaryAction: PrimaryActionButton(
        label: l.journalSaveReminders,
        loading: _busy,
        onPressed: () async {
          setState(() => _busy = true);
          try {
            final n = ref.read(notificationServiceProvider);
            if (s.mealReminders.isNotEmpty && !await n.requestPermission()) {
              if (context.mounted) showMessage(context, l.journalNotificationsOff, error: true);
              return;
            }
            await n.cancelRange(NotificationIds.mealBase, MealType.values.length);
            final skipped = <String>[];
            for (final m in MealType.values) {
              final t = s.mealReminders[m.name];
              if (t == null) continue;
              final st = ScheduledTime.parse(t);
              if (isInQuietHours(st, s.quietHoursStart, s.quietHoursEnd)) {
                skipped.add(localizedLabel(l, m));
                continue;
              }
              await n.scheduleDaily(id: NotificationIds.mealBase + m.index, time: st, title: l.journalReminderNotificationTitle(localizedLabel(l, m)), body: l.journalReminderNotificationBody, payload: '/today');
            }
            await ref.read(profileRepoProvider).saveSettings(ref.read(uidProvider)!, s);
            if (context.mounted) {
              context.pop();
              showMessage(context, skipped.isEmpty ? l.journalRemindersSaved : l.journalRemindersSavedSkipped(skipped.length, skipped.join(', ')));
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
      children: [
        for (final m in MealType.values)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: SwitchListTile(
              title: Text(context.labelOf(m)),
              subtitle: Text(s.mealReminders[m.name] ?? l.journalReminderOff),
              value: s.mealReminders.containsKey(m.name),
              onChanged: (v) async {
                final map = Map<String, String>.from(s.mealReminders);
                if (v) {
                  final def = defaultMealTimes[m]!.split(':').map(int.parse).toList();
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: def[0], minute: def[1]));
                  if (t == null) return;
                  map[m.name] = '${two(t.hour)}:${two(t.minute)}';
                } else {
                  map.remove(m.name);
                }
                setState(() => _s = s.copyWith(mealReminders: map));
              },
            ),
          ),
        SectionHeader(l.journalQuietHours),
        Text(l.journalQuietHoursRange(two(s.quietHoursStart), two(s.quietHoursEnd)), style: context.text.bodyMedium),
        Semantics(label: l.journalQuietHours, child: RangeSlider(
          values: RangeValues(s.quietHoursEnd.toDouble(), s.quietHoursStart.toDouble()),
          min: 0,
          max: 23,
          divisions: 23,
          labels: RangeLabels(l.journalWakeLabel(two(s.quietHoursEnd)), l.journalSleepLabel(two(s.quietHoursStart))),
          onChanged: (v) => setState(() => _s = s.copyWith(quietHoursEnd: v.start.round(), quietHoursStart: v.end.round())),
        )),
        Text(l.journalRemindersFootnote, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 57 Eating patterns

class EatingPatternsScreen extends ConsumerWidget {
  const EatingPatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const days = 14;
    final meals = ref.watch(journalProvider(lastDays(days))).value ?? const <MealConsumption>[];
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final now = DateTime.now();
    final perDay = <int, int>{};
    for (final m in meals) {
      final local = m.eatenAt.toLocal();
      final idx = DateTime(now.year, now.month, now.day).difference(DateTime(local.year, local.month, local.day)).inDays;
      perDay[idx] = (perDay[idx] ?? 0) + 1;
    }
    final gaps = [for (var i = 1; i < days; i++) if (!perDay.containsKey(i)) i];
    final avgMinutes = <MealType, int>{};
    for (final t in MealType.values) {
      final ts = meals.where((m) => m.mealType == t).map((m) => m.eatenAt.toLocal().hour * 60 + m.eatenAt.toLocal().minute).toList();
      if (ts.isNotEmpty) avgMinutes[t] = ts.reduce((a, b) => a + b) ~/ ts.length;
    }
    int? adherence(MealType t) {
      final target = settings.mealReminders[t.name];
      if (target == null) return null;
      final p = target.split(':').map(int.parse).toList();
      final tm = p[0] * 60 + p[1];
      final ts = meals.where((m) => m.mealType == t).toList();
      if (ts.isEmpty) return null;
      final within = ts.where((m) => ((m.eatenAt.toLocal().hour * 60 + m.eatenAt.toLocal().minute) - tm).abs() <= 60).length;
      return (within * 100 / ts.length).round();
    }

    String hm(int mins) => formatTime(context, DateTime(2000, 1, 1, mins ~/ 60, mins % 60));
    final l = context.l10n;
    final tag = localeTag(context);
    String perDayAvg() {
      final s = (meals.length / days).toStringAsFixed(1);
      return tag.startsWith('fr') ? s.replaceAll('.', ',') : s;
    }

    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.journalEyebrow, title: l.journalEatingPatterns, subtitle: l.journalPatternsSubtitle),
      children: [
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(perDayAvg(), style: context.metric), Text(l.journalMealsPerDay, style: context.text.bodySmall)]))),
          const SizedBox(width: Space.xs),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(gaps.length.toString(), style: context.metric), Text(l.journalDaysNoRecords, style: context.text.bodySmall)]))),
        ]),
        SectionHeader(l.journalUsualTimes),
        if (avgMinutes.isEmpty) Text(l.journalPatternsEmpty, style: context.text.bodyMedium),
        for (final e in avgMinutes.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.labelOf(e.key)),
            subtitle: adherence(e.key) == null ? null : Text(l.journalWithinHour(adherence(e.key)!)),
            trailing: Text(l.journalAround(hm(e.value)), style: context.text.titleSmall),
          ),
        SectionHeader(l.journalLast14Days),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = days - 1; i >= 0; i--)
            Semantics(
              label: l.journalDayMealsSemantics(perDay[i] ?? 0, DateFormat.MMMd(tag).format(now.subtract(Duration(days: i)))),
              excludeSemantics: true,
              child: Container(
                width: 36,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (perDay[i] ?? 0) == 0 ? context.palette.hairline : context.palette.surfaceSoft,
                  borderRadius: BorderRadius.circular(Radii.s),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(DateFormat.E(tag).format(now.subtract(Duration(days: i))).substring(0, 1).toUpperCase(), style: context.text.labelSmall),
                  Text((perDay[i] ?? 0).toString(), style: context.text.titleSmall),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: Space.l),
        Text(
          l.journalPatternsDisclaimer,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}
