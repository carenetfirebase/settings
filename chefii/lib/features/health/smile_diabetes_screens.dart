import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/health.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/profile.dart';
import '../../domain/nutrition/evidence_library.dart';
import '../journal/journal_screens.dart';

// ---------------------------------------------------------------- 65 Smile & Food

class SmileAndFoodScreen extends ConsumerWidget {
  const SmileAndFoodScreen({super.key});

  static const _quick = [
    OralExposureKind.sugaryDrink,
    OralExposureKind.sweetSnack,
    OralExposureKind.stickyFood,
    OralExposureKind.acidicDrink,
    OralExposureKind.citrus,
    OralExposureKind.sipping,
    OralExposureKind.water,
    OralExposureKind.cheese,
    OralExposureKind.brushed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wellness = ref.watch(wellnessProvider).value ?? const WellnessPreferences();
    final events = ref.watch(oralProvider).value ?? const <OralExposureEvent>[];
    final today = DateTime.now();
    final todays = events.where((e) => DateUtils.isSameDay(e.occurredAt.toLocal(), today)).toList();
    final sugar = todays.where((e) => const {OralExposureKind.sugaryDrink, OralExposureKind.sweetSnack, OralExposureKind.stickyFood}.contains(e.kind)).length;
    final acid = todays.where((e) => const {OralExposureKind.acidicDrink, OralExposureKind.citrus, OralExposureKind.sipping}.contains(e.kind)).length;
    final helpful = todays.where((e) => e.kind.isProtective).length;

    if (!wellness.smileAndFood) {
      return PremiumAppScaffold(
        header: const EditorialPageHeader(eyebrow: 'Wellness', title: 'Smile & Food', subtitle: 'Learn how the timing of sugary and acidic foods affects your teeth.'),
        primaryAction: PrimaryActionButton(
          label: 'Turn on Smile & Food',
          onPressed: () => ref.read(profileRepoProvider).saveWellness(ref.read(uidProvider)!, wellness.copyWith(smileAndFood: true)),
        ),
        children: [
          Text('This is optional education. It isn\'t a dental assessment, and your entries stay private unless you choose to share them.', style: context.text.bodyMedium),
        ],
      );
    }

    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Wellness', title: 'Smile & Food', subtitle: 'Tap to log. It\'s about frequency and timing, not perfection.'),
      actions: [IconButton(tooltip: 'History', onPressed: () => context.push('/you/smile/history'), icon: const Icon(Icons.history))],
      children: [
        Row(children: [
          Expanded(child: _Count(value: sugar, label: 'sugar exposures today')),
          const SizedBox(width: Space.xs),
          Expanded(child: _Count(value: acid, label: 'acid exposures today')),
          const SizedBox(width: Space.xs),
          Expanded(child: _Count(value: helpful, label: 'helpful habits')),
        ]),
        const SectionHeader('Log now'),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          for (final k in _quick)
            ActionChip(
              avatar: Icon(k.isProtective ? Icons.water_drop_outlined : Icons.add, size: 18),
              label: Text(k.label),
              onPressed: () async {
                await ref.read(healthRepoProvider).addOral(ref.read(uidProvider)!, k, DateTime.now(), durationMinutes: k == OralExposureKind.sipping ? 30 : null);
                if (context.mounted) showMessage(context, '${k.label} logged');
              },
            ),
        ]),
        const SectionHeader('Kinder choices'),
        for (final (title, body) in [
          ('Keep sweets with meals', 'One sugar exposure at dinner is gentler on teeth than the same amount spread through the afternoon.'),
          ('Finish with water or cheese', 'Rinsing with water or ending on cheese helps your mouth recover after eating.'),
          ('Sip, then stop', 'If you enjoy juice or soda, drinking it with a meal rather than over an hour limits acid time.'),
          ('Wait to brush after acid', 'Many dental professionals suggest waiting a while after acidic food or drink before brushing. Ask your dentist what\'s right for you.'),
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.sentiment_satisfied_alt_outlined), title: Text(title), subtitle: Text(body)),
        const SectionHeader('Evidence'),
        for (final c in evidenceClaims.where((c) => c.topic == 'Teeth'))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: EvidenceReferenceCard(claim: c, sources: [for (final s in c.sourceIds) evidenceSources[s]!], onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
          ),
        Text('Education only. For tooth pain, sensitivity or concerns, see your dentist.', style: context.text.bodySmall),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => SoftCard(
        semanticLabel: '$value $label',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: context.metric),
          Text(label, style: context.text.bodySmall),
        ]),
      );
}

// ---------------------------------------------------------------- 66 Dental exposure history

class DentalHistoryScreen extends ConsumerWidget {
  const DentalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(oralProvider).value ?? const <OralExposureEvent>[];
    final byDay = <String, List<OralExposureEvent>>{};
    for (final e in events) {
      byDay.putIfAbsent(DateFormat('yyyy-MM-dd').format(e.occurredAt.toLocal()), () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final last7 = events.where((e) => e.occurredAt.isAfter(DateTime.now().subtract(const Duration(days: 7))) && !e.kind.isProtective).length;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Smile & Food', title: 'History', subtitle: events.isEmpty ? null : 'About ${(last7 / 7).toStringAsFixed(1)} sugar or acid exposures a day this week'),
      children: [
        if (events.isEmpty) const EmptyState(icon: Icons.history, title: 'Nothing logged yet', message: 'Your log will appear here.'),
        for (final d in days) ...[
          SectionHeader(formatDay(context, DateTime.parse(d)), topSpacing: Space.m),
          for (final e in byDay[d]!..sort((a, b) => a.occurredAt.compareTo(b.occurredAt)))
            DentalExposureCard(event: e, onDelete: () => ref.read(healthRepoProvider).deleteOral(e.uid, e.id)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 58 Optional diabetes setup

bool diabetesEnabled(WidgetRef ref) {
  final w = ref.watch(wellnessProvider).value;
  final consents = ref.watch(consentsProvider).value ?? const <ConsentRecord>[];
  return (w?.diabetesFeatures ?? false) && ProfileRepository.hasConsent(consents, 'diabetes_features');
}

class DiabetesSetupScreen extends ConsumerStatefulWidget {
  const DiabetesSetupScreen({super.key});

  @override
  ConsumerState<DiabetesSetupScreen> createState() => _DiabetesSetupScreenState();
}

class _DiabetesSetupScreenState extends ConsumerState<DiabetesSetupScreen> {
  bool _understand = false;
  bool _consent = false;
  GlucoseUnit _unit = GlucoseUnit.mmolL;

  static const consentText =
      'I choose to store glucose readings I enter in Chefii. I understand Chefii does not diagnose, interpret readings, recommend '
      'insulin or medication, or replace my glucose meter\'s or CGM\'s alarms. My readings are private and only shared if I grant access.';

  @override
  Widget build(BuildContext context) {
    final enabled = diabetesEnabled(ref);
    final uid = ref.watch(uidProvider);
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Optional', title: 'Glucose journal', subtitle: 'For people who already track glucose and want it alongside their meals.'),
      primaryAction: enabled
          ? SecondaryActionButton(
              label: 'Turn off glucose features',
              onPressed: () async {
                await ref.read(profileRepoProvider).recordConsent(uid!, purpose: 'diabetes_features', granted: false);
                final w = ref.read(wellnessProvider).value ?? const WellnessPreferences();
                await ref.read(profileRepoProvider).saveWellness(uid, w.copyWith(diabetesFeatures: false));
              },
            )
          : PrimaryActionButton(
              label: 'Turn on glucose journal',
              onPressed: _understand && _consent
                  ? () async {
                      await ref.read(profileRepoProvider).recordConsent(uid!, purpose: 'diabetes_features', granted: true, text: consentText);
                      final w = ref.read(wellnessProvider).value ?? const WellnessPreferences();
                      await ref.read(profileRepoProvider).saveWellness(uid, w.copyWith(diabetesFeatures: true));
                      final s = ref.read(settingsProvider).value ?? const AppSettings();
                      await ref.read(profileRepoProvider).saveSettings(uid, s);
                      if (context.mounted) context.pushReplacement('/you/glucose?unit=${_unit.name}');
                    }
                  : null,
            ),
      children: [
        if (enabled) ...[
          SoftCard(color: context.palette.successSoft, child: const Text('Glucose journal is on.')),
          const SizedBox(height: Space.s),
          SecondaryActionButton(label: 'Open glucose journal', onPressed: () => context.push('/you/glucose')),
          const SizedBox(height: Space.m),
        ],
        for (final (icon, text) in [
          (Icons.edit_note, 'Record readings you take, with the time and context.'),
          (Icons.timeline, 'See them next to the meals in your journal.'),
          (Icons.block, 'No predictions, scores, diagnoses or dosing advice — ever.'),
          (Icons.notifications_off_outlined, 'Not an alarm. Keep using your meter or CGM alerts.'),
          (Icons.lock_outline, 'Private to you. Shared only with a professional you choose.'),
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text)),
        if (!enabled) ...[
          const SectionHeader('Units'),
          SegmentedButton<GlucoseUnit>(
            segments: [for (final u in GlucoseUnit.values) ButtonSegment(value: u, label: Text(u.label))],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
          const SizedBox(height: Space.m),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _understand,
            onChanged: (v) => setState(() => _understand = v ?? false),
            title: const Text('I understand this is a journal, not a medical device'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: const Text('I consent to Chefii storing my glucose readings'),
            subtitle: const Text(consentText),
          ),
          const SizedBox(height: Space.s),
          Text('If you have symptoms of very high or low blood sugar, follow your care plan or seek medical help.', style: context.text.bodySmall?.copyWith(color: context.palette.error)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- 59 Glucose journal

class GlucoseJournalScreen extends ConsumerStatefulWidget {
  const GlucoseJournalScreen({super.key, this.unit});
  final String? unit;

  @override
  ConsumerState<GlucoseJournalScreen> createState() => _GlucoseJournalScreenState();
}

class _GlucoseJournalScreenState extends ConsumerState<GlucoseJournalScreen> {
  late GlucoseUnit _unit = widget.unit == null ? GlucoseUnit.mmolL : GlucoseUnit.values.byName(widget.unit!);
  final _value = TextEditingController();
  GlucoseContext _ctx = GlucoseContext.other;
  DateTime _at = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final v = double.tryParse(_value.text.replaceAll(',', '.'));
    if (v == null) return setState(() => _error = 'Enter a number.');
    final err = GlucoseEntry.validate(v, _unit);
    if (err != null) return setState(() => _error = err);
    await ref.read(healthRepoProvider).addGlucose(uid: ref.read(uidProvider)!, value: v, unit: _unit, measuredAt: _at, context: _ctx);
    _value.clear();
    setState(() {
      _error = null;
      _at = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!diabetesEnabled(ref)) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.lock_outline, title: 'Glucose journal is off', message: 'Turn it on with explicit consent first.', actionLabel: 'Set up', onAction: () => context.pushReplacement('/you/diabetes')),
      ]);
    }
    final entries = ref.watch(glucoseProvider).value ?? const <GlucoseEntry>[];
    String fmt(GlucoseEntry e) => '${e.valueIn(_unit).toStringAsFixed(_unit == GlucoseUnit.mmolL ? 1 : 0)} ${_unit.label}';
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Glucose', title: 'Glucose journal', subtitle: 'Your readings, as you entered them.'),
      actions: [IconButton(tooltip: 'Timeline with meals', onPressed: () => context.push('/you/glucose/timeline'), icon: const Icon(Icons.timeline))],
      primaryAction: PrimaryActionButton(label: 'Add reading', onPressed: _add),
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Reading', suffixText: _unit.label, errorText: _error),
            ),
          ),
          const SizedBox(width: Space.xs),
          SegmentedButton<GlucoseUnit>(
            segments: [for (final u in GlucoseUnit.values) ButtonSegment(value: u, label: Text(u.label))],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
        ]),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, children: [
          for (final c in GlucoseContext.values)
            ChoiceChip(
              label: Text(switch (c) { GlucoseContext.fasting => 'Fasting', GlucoseContext.beforeMeal => 'Before meal', GlucoseContext.afterMeal => 'After meal', GlucoseContext.bedtime => 'Bedtime', GlucoseContext.other => 'Other' }),
              selected: _ctx == c,
              onSelected: (_) => setState(() => _ctx = c),
            ),
        ]),
        Card(
          margin: const EdgeInsets.only(top: Space.s),
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text('${formatDay(context, _at)} at ${formatTime(context, _at)}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
              if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
            },
          ),
        ),
        const SectionHeader('Readings'),
        if (entries.isEmpty) Text('No readings yet.', style: context.text.bodyMedium),
        for (final e in entries)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(fmt(e), style: context.text.titleMedium),
              subtitle: Text('${formatDay(context, e.measuredAt)} ${formatTime(context, e.measuredAt)} · ${e.context.name} · ${switch (e.source) { GlucoseSource.manual => 'entered by you', GlucoseSource.healthIntegration => 'from Health app', GlucoseSource.device => 'from ${e.deviceName ?? 'device'}' }}'
                  '${e.enteredUnit != _unit ? ' · entered as ${e.valueIn(e.enteredUnit).toStringAsFixed(1)} ${e.enteredUnit.label}' : ''}'),
              trailing: IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(healthRepoProvider).deleteGlucose(e.uid, e.id)),
            ),
          ),
        const SizedBox(height: Space.m),
        Text('Reading from Apple Health or Health Connect isn\'t available yet. Chefii never interprets readings.', style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 60 Glucose & meal timeline

class GlucoseTimelineScreen extends ConsumerStatefulWidget {
  const GlucoseTimelineScreen({super.key});

  @override
  ConsumerState<GlucoseTimelineScreen> createState() => _GlucoseTimelineScreenState();
}

class _GlucoseTimelineScreenState extends ConsumerState<GlucoseTimelineScreen> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) {
    if (!diabetesEnabled(ref)) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.lock_outline, title: 'Glucose journal is off', message: 'Turn it on first.', actionLabel: 'Set up', onAction: () => context.pushReplacement('/you/diabetes')),
      ]);
    }
    final meals = ref.watch(journalProvider(dayRange(_day))).value ?? const <MealConsumption>[];
    final readings = (ref.watch(glucoseProvider).value ?? const <GlucoseEntry>[]).where((g) => DateUtils.isSameDay(g.measuredAt.toLocal(), _day));
    final items = <(DateTime, Widget)>[
      for (final m in meals)
        (m.eatenAt, ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.restaurant), title: Text(m.title), subtitle: Text('${m.mealType.label} · ${formatTime(context, m.eatenAt)}'))),
      for (final g in readings)
        (g.measuredAt, ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.water_drop_outlined, color: context.palette.info),
          title: Text('${g.valueIn(g.enteredUnit).toStringAsFixed(g.enteredUnit == GlucoseUnit.mmolL ? 1 : 0)} ${g.enteredUnit.label}'),
          subtitle: Text('${g.context.name} · ${formatTime(context, g.measuredAt)}'),
        )),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Glucose',
        title: formatDay(context, _day),
        subtitle: 'Meals and readings in order. No interpretation.',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Previous day', onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: 'Next day', onPressed: DateUtils.isSameDay(_day, DateTime.now()) ? null : () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      children: [
        if (items.isEmpty) const EmptyState(compact: true, icon: Icons.timeline, title: 'Nothing recorded', message: 'Meals and readings for this day will appear here.'),
        for (final (_, w) in items) w,
        const SizedBox(height: Space.m),
        Text('Discuss patterns with your diabetes care team. Chefii does not replace glucose alarms or medical advice.', style: context.text.bodySmall),
      ],
    );
  }
}
