import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../core/services/analytics.dart';
import '../../core/services/notification_service.dart';
import '../../domain/models/codec.dart';
import '../../domain/models/planning.dart';
import '../../domain/models/recipe.dart';
import '../../domain/recipes/recipe_availability.dart';
import '../shared/recipe_logic.dart';

/// Morning timeline from wake to door for a given day.
List<(String, DateTime)> morningTimeline(MorningRoutine r, CalendarDate day, Recipe? breakfast) {
  DateTime at(String hhmm) {
    final p = hhmm.split(':').map(int.parse).toList();
    return DateTime(day.year, day.month, day.day, p[0], p[1]);
  }

  final wake = at(r.wakeTime);
  final leave = at(r.departureTime);
  final readyBy = leave.subtract(Duration(minutes: r.bufferMinutes));
  final cook = breakfast?.totalMinutes ?? 5;
  const eat = 15, tidy = 5;
  final eatAt = readyBy.subtract(const Duration(minutes: eat + tidy));
  var cookAt = eatAt.subtract(Duration(minutes: cook));
  if (cookAt.isBefore(wake)) cookAt = wake;
  return [
    ('Wake', wake),
    ('Get ready', wake.add(const Duration(minutes: 5))),
    if (breakfast != null) ('Make ${breakfast.title}', cookAt),
    ('Eat', eatAt),
    ('Tidy up', eatAt.add(const Duration(minutes: eat))),
    ('Leave', leave),
  ];
}

/// Picks breakfasts that fit the free time and the breakfast style.
List<AvailabilityReport> breakfastOptions(WidgetRef ref, MorningRoutine r) {
  final ranked = ref.watch(rankedRecipesProvider((mealType: MealType.breakfast, maxMinutes: r.availableMinutes.clamp(5, 120), tag: null)));
  if (r.breakfastStyle == 'no_cook' || r.breakfastStyle == 'grab_and_go') {
    final noCook = ranked.where((a) => a.recipe.tags.contains('no-cook')).toList();
    if (noCook.isNotEmpty) return noCook;
  }
  return ranked;
}

// ---------------------------------------------------------------- 39 Morning setup

class MorningSetupScreen extends ConsumerStatefulWidget {
  const MorningSetupScreen({super.key});

  @override
  ConsumerState<MorningSetupScreen> createState() => _MorningSetupScreenState();
}

class _MorningSetupScreenState extends ConsumerState<MorningSetupScreen> {
  MorningRoutine? _r;
  bool _busy = false;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  Future<String?> _pickTime(String current) async {
    final p = current.split(':').map(int.parse).toList();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: p[0], minute: p[1]));
    return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r ??= ref.watch(morningRoutineProvider).value;
    if (r == null) return const Scaffold(body: LoadingState());
    void set(MorningRoutine n) => setState(() => _r = n);
    final invalid = r.availableMinutes <= 0;
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Mornings', title: 'A calmer morning', subtitle: 'Tell us when you wake and when you leave. We\'ll plan the bit in between.'),
      primaryAction: PrimaryActionButton(
        label: 'Continue',
        loading: _busy,
        onPressed: invalid || r.weekdays.isEmpty
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await ref.read(profileRepoProvider).saveMorningRoutine(ref.read(uidProvider)!, r.copyWith(enabled: true));
                  ref.read(analyticsProvider).log(AnalyticsEvents.routineEnabled);
                  if (context.mounted) context.pushReplacement('/morning/alarm');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
      children: [
        Text('On these days', style: context.text.titleMedium),
        const SizedBox(height: Space.xs),
        Wrap(spacing: Space.xs, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(_days[d - 1], semanticsLabel: _dayNames[d - 1]),
              selected: r.weekdays.contains(d),
              showCheckmark: false,
              onSelected: (v) => set(r.copyWith(weekdays: v ? ([...r.weekdays, d]..sort()) : (r.weekdays.where((x) => x != d).toList()))),
            ),
        ]),
        const SizedBox(height: Space.l),
        _TimeRow(label: 'Wake up', value: r.wakeTime, onTap: () async {
          final t = await _pickTime(r.wakeTime);
          if (t != null) set(r.copyWith(wakeTime: t));
        }),
        _TimeRow(label: 'Out the door by', value: r.departureTime, onTap: () async {
          final t = await _pickTime(r.departureTime);
          if (t != null) set(r.copyWith(departureTime: t));
        }),
        const SizedBox(height: Space.s),
        Text('Buffer before leaving: ${r.bufferMinutes} min', style: context.text.bodyMedium),
        Semantics(label: 'Buffer before leaving', child: Slider(value: r.bufferMinutes.toDouble(), max: 30, divisions: 6, label: '${r.bufferMinutes} min', onChanged: (v) => set(r.copyWith(bufferMinutes: v.round())))),
        Text(
          invalid ? 'Your departure time needs to be after your wake time plus the buffer.' : 'That leaves ${r.availableMinutes} minutes for getting ready and breakfast.',
          style: context.text.bodySmall?.copyWith(color: invalid ? context.palette.error : null),
        ),
        const SectionHeader('Breakfast style'),
        ChoiceChipGroup(
          single: true,
          options: const ['quick', 'cooked', 'no_cook', 'grab_and_go'],
          labelOf: (s) => switch (s) { 'quick' => 'Quick & simple', 'cooked' => 'Something warm', 'no_cook' => 'No cooking', _ => 'Grab and go' },
          selected: {r.breakfastStyle},
          onChanged: (s) => s.isEmpty ? null : set(r.copyWith(breakfastStyle: s.first)),
        ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: Space.xs),
        child: ListTile(
          title: Text(label),
          trailing: Text(value, style: context.text.headlineSmall),
          onTap: onTap,
        ),
      );
}

// ---------------------------------------------------------------- 40 Alarm settings

class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
  bool _busy = false;
  String? _scheduled;

  Future<void> _apply(MorningRoutine r, {required bool alarm, required bool preview}) async {
    setState(() => _busy = true);
    try {
      final n = ref.read(notificationServiceProvider);
      final granted = await n.requestPermission(exactAlarms: alarm);
      if (!granted) {
        if (mounted) showMessage(context, 'Notifications are off for Chefii. Turn them on in Settings to use alarms.', error: true);
        return;
      }
      await n.cancelRange(NotificationIds.morningAlarmBase, 8);
      await n.cancelRange(NotificationIds.eveningPreviewBase, 8);
      if (alarm) {
        await n.scheduleWeekly(
          baseId: NotificationIds.morningAlarmBase,
          weekdays: r.weekdays,
          time: ScheduledTime.parse(r.wakeTime),
          title: 'Good morning',
          body: 'Your morning plan is ready.',
          payload: '/morning/wake',
          alarm: true,
        );
      }
      if (preview) {
        // The evening before each routine day.
        final eves = r.weekdays.map((d) => d == 1 ? 7 : d - 1).toList();
        await n.scheduleWeekly(
          baseId: NotificationIds.eveningPreviewBase,
          weekdays: eves,
          time: ScheduledTime.parse(r.eveningPreviewTime),
          title: 'Tomorrow\'s breakfast',
          body: 'Take a look at tomorrow morning\'s plan.',
          payload: '/morning/evening',
        );
      }
      await ref.read(profileRepoProvider).saveMorningRoutine(ref.read(uidProvider)!, r.copyWith(alarmEnabled: alarm));
      setState(() => _scheduled = [
            if (alarm) 'Alarm at ${r.wakeTime}',
            if (preview) 'Evening preview at ${r.eveningPreviewTime}',
          ].join(' · '));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _preview = true;
  bool? _alarm;

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final alarm = _alarm ?? r.alarmEnabled;
    return Builder(builder: (context) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(eyebrow: 'Mornings', title: 'Alarm & reminders'),
        primaryAction: PrimaryActionButton(label: 'Save schedule', loading: _busy, onPressed: () => _apply(r, alarm: alarm, preview: _preview)),
        children: [
          ToggleTile(
            icon: Icons.alarm,
            title: 'Wake me with Chefii',
            subtitle: 'An alarm at ${r.wakeTime} that opens your morning plan',
            value: alarm,
            onChanged: (v) => setState(() => _alarm = v),
          ),
          ToggleTile(
            icon: Icons.nightlight_outlined,
            title: 'Evening preview',
            subtitle: 'A gentle note at ${r.eveningPreviewTime} with tomorrow\'s breakfast',
            value: _preview,
            onChanged: (v) => setState(() => _preview = v),
          ),
          const SizedBox(height: Space.m),
          SoftCard(
            color: context.palette.infoSoft,
            child: Text(
              'On Android, Chefii uses a system alarm clock entry. On iPhone, it uses a time-sensitive notification that respects Focus settings; it isn\'t a replacement for the Clock app, so keep a backup alarm for anything critical.',
              style: context.text.bodySmall?.copyWith(color: context.palette.ink),
            ),
          ),
          if (_scheduled != null) ...[
            const SizedBox(height: Space.m),
            Semantics(
              liveRegion: true,
              child: SoftCard(
                color: context.palette.successSoft,
                child: Row(children: [
                  Icon(Icons.check_circle, color: context.palette.success),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(_scheduled!.isEmpty ? 'All morning notifications are off.' : 'Scheduled: $_scheduled', style: context.text.bodyMedium)),
                ]),
              ),
            ),
            TextButton(onPressed: () => context.pushReplacement('/morning/evening'), child: const Text('See tomorrow\'s plan')),
          ],
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- 41 Evening preview

class EveningPreviewScreen extends ConsumerWidget {
  const EveningPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final tomorrow = ref.watch(todayProvider).addDays(1);
    final plan = ref.watch(mealPlanProvider(tomorrow)).value ?? const <MealPlanEntry>[];
    final planned = plan.where((e) => e.date == tomorrow && e.mealType == MealType.breakfast).firstOrNull;
    final options = breakfastOptions(ref, r);
    final chosenId = planned?.recipeId ?? r.tomorrowRecipeId ?? options.firstOrNull?.recipe.id;
    final recipe = chosenId == null ? null : ref.watch(recipeByIdProvider(chosenId));
    final report = recipe == null ? null : ref.watch(recipeAvailabilityProvider(recipe));
    final timeline = morningTimeline(r, tomorrow, recipe);
    final isRoutineDay = r.weekdays.contains(tomorrow.toLocalDateTime().weekday);

    if (!r.enabled) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.wb_twilight, title: 'Set up your mornings', message: 'Chefii can plan breakfast around your wake and leave times.', actionLabel: 'Set up', onAction: () => context.pushReplacement('/morning/setup')),
      ]);
    }
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Tomorrow', title: isRoutineDay ? 'Your morning, planned' : 'Tomorrow is a day off', subtitle: '${r.availableMinutes} minutes from ${r.wakeTime} to ${r.departureTime}'),
      actions: [IconButton(tooltip: 'Edit routine', onPressed: () => context.push('/morning/setup'), icon: const Icon(Icons.edit_outlined))],
      primaryAction: recipe == null ? null : PrimaryActionButton(label: 'Sounds good', onPressed: () async {
        await ref.read(profileRepoProvider).saveMorningRoutine(ref.read(uidProvider)!, r.copyWith(tomorrowRecipeId: recipe.id));
        if (context.mounted) {
          showMessage(context, 'Breakfast is set for tomorrow.');
          context.pop();
        }
      }),
      children: [
        if (recipe != null)
          LuxuryRecipeCard(recipe: recipe, compact: true, availabilityLabel: report?.label, canCookNow: report?.canCookNow ?? false, onTap: () => context.push('/recipe/${recipe.id}'))
        else
          const EmptyState(compact: true, icon: Icons.free_breakfast_outlined, title: 'No breakfast fits', message: 'Try a longer morning or a different breakfast style.'),
        if (report != null && !report.canCookNow)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text('Missing: ${report.missing.map((c) => c.ingredient.name).join(', ')}', style: context.text.bodySmall),
          ),
        const SectionHeader('Timeline'),
        for (var i = 0; i < timeline.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(width: 72, child: Text(formatTime(context, timeline[i].$2), style: context.text.labelLarge)),
            title: Text(timeline[i].$1),
          ),
        if (options.length > 1) ...[
          const SectionHeader('Or choose'),
          for (final o in options.where((o) => o.recipe.id != chosenId).take(4))
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(o.recipe.title),
                subtitle: Text('${formatMinutes(o.recipe.totalMinutes)} · ${o.label}'),
                trailing: const Icon(Icons.swap_horiz),
                onTap: () => ref.read(profileRepoProvider).saveMorningRoutine(ref.read(uidProvider)!, r.copyWith(tomorrowRecipeId: o.recipe.id)),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 42 Alarm entry

class MorningAlarmScreen extends ConsumerWidget {
  const MorningAlarmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surfaceSoft,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(children: [
            const Spacer(),
            Text(greetingFor(now), style: context.text.headlineMedium),
            const SizedBox(height: Space.s),
            Semantics(
              label: 'It is ${formatTime(context, now)}',
              child: ExcludeSemantics(child: Text(formatTime(context, now), style: context.text.displayLarge?.copyWith(fontSize: 72))),
            ),
            const Spacer(),
            PrimaryActionButton(
              label: 'I\'m up',
              icon: Icons.wb_sunny_outlined,
              onPressed: () async {
                final n = ref.read(notificationServiceProvider);
                await n.cancel(NotificationIds.generic);
                if (context.mounted) context.pushReplacement('/morning/checklist');
              },
            ),
            const SizedBox(height: Space.s),
            SecondaryActionButton(
              label: 'Snooze 9 minutes',
              onPressed: () async {
                await ref.read(notificationServiceProvider).scheduleIn(
                      id: NotificationIds.generic,
                      after: const Duration(minutes: 9),
                      title: 'Time to get up',
                      body: 'Snooze is over. Your morning plan is waiting.',
                      payload: '/morning/wake',
                    );
                if (context.mounted) context.go('/today');
              },
            ),
            const SizedBox(height: Space.l),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 43 Morning checklist

class MorningChecklistScreen extends ConsumerStatefulWidget {
  const MorningChecklistScreen({super.key});

  @override
  ConsumerState<MorningChecklistScreen> createState() => _MorningChecklistScreenState();
}

class _MorningChecklistScreenState extends ConsumerState<MorningChecklistScreen> {
  final _done = <String>{};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final today = ref.watch(todayProvider);
    final recipe = r.tomorrowRecipeId == null ? breakfastOptions(ref, r).firstOrNull?.recipe : ref.watch(recipeByIdProvider(r.tomorrowRecipeId!));
    final timeline = morningTimeline(r, today, recipe);
    final leave = timeline.last.$2;
    final left = leave.difference(DateTime.now());
    final late = timeline.where((t) => !_done.contains(t.$1) && t.$2.isBefore(DateTime.now())).length >= 2;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'This morning',
        title: left.isNegative ? 'Time to go' : '${left.inMinutes} min until you leave',
      ),
      primaryAction: recipe == null
          ? null
          : PrimaryActionButton(label: 'Make ${recipe.title.split(' ').take(3).join(' ')}', onPressed: () => context.push('/recipe/${recipe.id}')),
      children: [
        if (late)
          SoftCard(
            color: context.palette.warningSoft,
            onTap: () => context.push('/morning/late'),
            child: Row(children: [
              Icon(Icons.directions_run, color: context.palette.warning),
              const SizedBox(width: Space.s),
              const Expanded(child: Text('Running behind? See faster options')),
              const Icon(Icons.chevron_right),
            ]),
          ),
        for (final (label, at) in timeline)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _done.contains(label),
            onChanged: (v) => setState(() => v == true ? _done.add(label) : _done.remove(label)),
            title: Text(label, style: context.text.titleMedium),
            secondary: Text(formatTime(context, at), style: context.text.labelLarge),
          ),
        TextButton.icon(onPressed: () => context.push('/morning/late'), icon: const Icon(Icons.directions_run), label: const Text('I\'m running late')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 44 Running late

class RunningLateScreen extends ConsumerWidget {
  const RunningLateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(morningRoutineProvider).value ?? const MorningRoutine();
    final today = ref.watch(todayProvider);
    final leave = morningTimeline(r, today, null).last.$2;
    final minutes = leave.difference(DateTime.now()).inMinutes.clamp(0, 240);
    final ranked = ref.watch(rankedRecipesProvider((mealType: MealType.breakfast, maxMinutes: 10, tag: null)));
    final noCook = ranked.where((a) => a.recipe.tags.contains('no-cook') || a.recipe.cookMinutes == 0).toList();
    final quick = ranked.where((a) => !noCook.contains(a)).toList();
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'No stress', title: '$minutes minutes left', subtitle: 'Here\'s what still works.'),
      primaryAction: SecondaryActionButton(
        label: 'Skip breakfast today',
        onPressed: () {
          // Skipping never touches inventory.
          context.go('/today');
          showMessage(context, 'Skipped. Nothing in your kitchen was changed.');
        },
      ),
      children: [
        const SectionHeader('No cooking', topSpacing: 0),
        if (noCook.isEmpty) Text('Nothing no-cook fits your kitchen right now.', style: context.text.bodySmall),
        for (final a in noCook.take(3))
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(title: Text(a.recipe.title), subtitle: Text('${formatMinutes(a.recipe.totalMinutes)} · ${a.label}'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/recipe/${a.recipe.id}')),
          ),
        const SectionHeader('Ten minutes or less'),
        if (quick.isEmpty) Text('Nothing else fits in ten minutes.', style: context.text.bodySmall),
        for (final a in quick.take(3))
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(title: Text(a.recipe.title), subtitle: Text('${formatMinutes(a.recipe.totalMinutes)} · ${a.label}'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/recipe/${a.recipe.id}')),
          ),
      ],
    );
  }
}
