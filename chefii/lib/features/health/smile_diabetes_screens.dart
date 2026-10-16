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
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
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
    final l = context.l10n;

    if (!wellness.smileAndFood) {
      return PremiumAppScaffold(
        header: EditorialPageHeader(eyebrow: l.healthWellnessEyebrow, title: l.healthSmileAndFood, subtitle: l.healthSmileIntroSubtitle),
        primaryAction: PrimaryActionButton(
          label: l.healthTurnOnSmile,
          onPressed: () => ref.read(profileRepoProvider).saveWellness(ref.read(uidProvider)!, wellness.copyWith(smileAndFood: true)),
        ),
        children: [
          Text(l.healthSmileOptionalNote, style: context.text.bodyMedium),
        ],
      );
    }

    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthWellnessEyebrow, title: l.healthSmileAndFood, subtitle: l.healthSmileSubtitle),
      actions: [IconButton(tooltip: l.healthHistory, onPressed: () => context.push('/you/smile/history'), icon: const Icon(Icons.history))],
      children: [
        Row(children: [
          Expanded(child: _Count(value: sugar, label: l.healthSugarExposuresToday)),
          const SizedBox(width: Space.xs),
          Expanded(child: _Count(value: acid, label: l.healthAcidExposuresToday)),
          const SizedBox(width: Space.xs),
          Expanded(child: _Count(value: helpful, label: l.healthHelpfulHabits)),
        ]),
        SectionHeader(l.healthLogNow),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          for (final k in _quick)
            ActionChip(
              avatar: Icon(k.isProtective ? Icons.water_drop_outlined : Icons.add, size: 18),
              label: Text(context.labelOf(k)),
              onPressed: () async {
                await ref.read(healthRepoProvider).addOral(ref.read(uidProvider)!, k, DateTime.now(), durationMinutes: k == OralExposureKind.sipping ? 30 : null);
                if (context.mounted) showMessage(context, l.healthLoggedMessage(context.labelOf(k)));
              },
            ),
        ]),
        SectionHeader(l.healthKinderChoices),
        for (final (title, body) in [
          (l.healthTipSweetsTitle, l.healthTipSweetsBody),
          (l.healthTipFinishTitle, l.healthTipFinishBody),
          (l.healthTipSipTitle, l.healthTipSipBody),
          (l.healthTipBrushTitle, l.healthTipBrushBody),
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.sentiment_satisfied_alt_outlined), title: Text(title), subtitle: Text(body)),
        SectionHeader(l.healthEvidence),
        for (final c in evidenceClaims.where((c) => c.topic == 'Teeth')) // l10n-ignore: content topic key
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: EvidenceReferenceCard(claim: c, sources: [for (final s in c.sourceIds) evidenceSources[s]!], onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
          ),
        Text(l.healthSmileFooter, style: context.text.bodySmall),
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
        semanticLabel: '$value $label', // l10n-ignore: only translated values
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: context.metric), // l10n-ignore: number
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
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthSmileAndFood, title: l.healthHistory, subtitle: events.isEmpty ? null : l.healthHistoryExposuresPerDay(_decimal(context, last7 / 7, 1))),
      children: [
        if (events.isEmpty) EmptyState(icon: Icons.history, title: l.healthNothingLoggedYet, message: l.healthLogWillAppear),
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

  @override
  Widget build(BuildContext context) {
    final enabled = diabetesEnabled(ref);
    final uid = ref.watch(uidProvider);
    final l = context.l10n;
    // The consent record stores the exact wording the person agreed to, in
    // the language it was shown in.
    final consentText = l.healthDiabetesConsentText;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthOptionalEyebrow, title: l.healthGlucoseJournal, subtitle: l.healthDiabetesSubtitle),
      primaryAction: enabled
          ? SecondaryActionButton(
              label: l.healthTurnOffGlucose,
              onPressed: () async {
                await ref.read(profileRepoProvider).recordConsent(uid!, purpose: 'diabetes_features', granted: false);
                final w = ref.read(wellnessProvider).value ?? const WellnessPreferences();
                await ref.read(profileRepoProvider).saveWellness(uid, w.copyWith(diabetesFeatures: false));
              },
            )
          : PrimaryActionButton(
              label: l.healthTurnOnGlucose,
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
          SoftCard(color: context.palette.successSoft, child: Text(l.healthGlucoseOn)),
          const SizedBox(height: Space.s),
          SecondaryActionButton(label: l.healthOpenGlucose, onPressed: () => context.push('/you/glucose')),
          const SizedBox(height: Space.m),
        ],
        for (final (icon, text) in [
          (Icons.edit_note, l.healthDiabetesPointRecord),
          (Icons.timeline, l.healthDiabetesPointMeals),
          (Icons.block, l.healthDiabetesPointNoAdvice),
          (Icons.notifications_off_outlined, l.healthDiabetesPointNotAlarm),
          (Icons.lock_outline, l.healthDiabetesPointPrivate),
        ])
          ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text)),
        if (!enabled) ...[
          SectionHeader(l.healthUnits),
          SegmentedButton<GlucoseUnit>(
            segments: [for (final u in GlucoseUnit.values) ButtonSegment(value: u, label: Text(context.labelOf(u)))],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
          const SizedBox(height: Space.m),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _understand,
            onChanged: (v) => setState(() => _understand = v ?? false),
            title: Text(l.healthUnderstandJournal),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(l.healthConsentStore),
            subtitle: Text(consentText),
          ),
          const SizedBox(height: Space.s),
          Text(l.healthSymptomsWarning, style: context.text.bodySmall?.copyWith(color: context.palette.error)),
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
    final l = context.l10n;
    if (v == null) return setState(() => _error = l.healthEnterNumber);
    // Same checks as GlucoseEntry.validate, with translated messages.
    if (GlucoseEntry.validate(v, _unit) != null) {
      return setState(() => _error = GlucoseEntry.toMmol(v, _unit) <= 0 ? l.healthEnterPositive : l.healthValueOutOfRange);
    }
    await ref.read(healthRepoProvider).addGlucose(uid: ref.read(uidProvider)!, value: v, unit: _unit, measuredAt: _at, context: _ctx);
    _value.clear();
    setState(() {
      _error = null;
      _at = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (!diabetesEnabled(ref)) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.lock_outline, title: l.healthGlucoseOffTitle, message: l.healthGlucoseOffConsent, actionLabel: l.healthSetUp, onAction: () => context.pushReplacement('/you/diabetes')),
      ]);
    }
    final entries = ref.watch(glucoseProvider).value ?? const <GlucoseEntry>[];
    String fmt(GlucoseEntry e) => _reading(context, e.valueIn(_unit), _unit);
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthGlucoseEyebrow, title: l.healthGlucoseJournal, subtitle: l.healthGlucoseSubtitle),
      actions: [IconButton(tooltip: l.healthTimelineWithMeals, onPressed: () => context.push('/you/glucose/timeline'), icon: const Icon(Icons.timeline))],
      primaryAction: PrimaryActionButton(label: l.healthAddReading, onPressed: _add),
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.healthReading, suffixText: context.labelOf(_unit), errorText: _error),
            ),
          ),
          const SizedBox(width: Space.xs),
          SegmentedButton<GlucoseUnit>(
            segments: [for (final u in GlucoseUnit.values) ButtonSegment(value: u, label: Text(context.labelOf(u)))],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
        ]),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.xs, children: [
          for (final c in GlucoseContext.values)
            ChoiceChip(
              label: Text(_contextLabel(l, c)),
              selected: _ctx == c,
              onSelected: (_) => setState(() => _ctx = c),
            ),
        ]),
        Card(
          margin: const EdgeInsets.only(top: Space.s),
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text(l.healthDayAtTime(formatDay(context, _at), formatTime(context, _at))),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
              if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
            },
          ),
        ),
        SectionHeader(l.healthReadings),
        if (entries.isEmpty) Text(l.healthNoReadings, style: context.text.bodyMedium),
        for (final e in entries)
          Card(
            margin: const EdgeInsets.only(bottom: Space.xs),
            child: ListTile(
              title: Text(fmt(e), style: context.text.titleMedium),
              subtitle: Text([
                '${formatDay(context, e.measuredAt)} ${formatTime(context, e.measuredAt)}',
                _contextLabel(l, e.context),
                switch (e.source) {
                  GlucoseSource.manual => l.healthSourceManual,
                  GlucoseSource.healthIntegration => l.healthSourceHealthApp,
                  GlucoseSource.device => e.deviceName == null ? l.healthSourceDevice(l.healthDevice) : l.healthSourceDevice(e.deviceName!),
                },
                if (e.enteredUnit != _unit) l.healthEnteredAs(_reading(context, e.valueIn(e.enteredUnit), e.enteredUnit, digits: 1)),
              ].join(' · ')),
              trailing: IconButton(tooltip: l.healthDelete, icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(healthRepoProvider).deleteGlucose(e.uid, e.id)),
            ),
          ),
        const SizedBox(height: Space.m),
        Text(l.healthNoHealthImport, style: context.text.bodySmall),
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
    final l = context.l10n;
    if (!diabetesEnabled(ref)) {
      return PremiumAppScaffold(children: [
        EmptyState(icon: Icons.lock_outline, title: l.healthGlucoseOffTitle, message: l.healthGlucoseOffShort, actionLabel: l.healthSetUp, onAction: () => context.pushReplacement('/you/diabetes')),
      ]);
    }
    final meals = ref.watch(journalProvider(dayRange(_day))).value ?? const <MealConsumption>[];
    final readings = (ref.watch(glucoseProvider).value ?? const <GlucoseEntry>[]).where((g) => DateUtils.isSameDay(g.measuredAt.toLocal(), _day));
    final items = <(DateTime, Widget)>[
      for (final m in meals)
        (m.eatenAt, ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.restaurant), title: Text(m.title), subtitle: Text('${context.labelOf(m.mealType)} · ${formatTime(context, m.eatenAt)}'))), // l10n-ignore: only translated values
      for (final g in readings)
        (g.measuredAt, ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.water_drop_outlined, color: context.palette.info),
          title: Text(_reading(context, g.valueIn(g.enteredUnit), g.enteredUnit)),
          subtitle: Text('${_contextLabel(l, g.context)} · ${formatTime(context, g.measuredAt)}'), // l10n-ignore: only translated values
        )),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l.healthGlucoseEyebrow,
        title: formatDay(context, _day),
        subtitle: l.healthTimelineSubtitle,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: l.healthPreviousDay, onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: l.healthNextDay, onPressed: DateUtils.isSameDay(_day, DateTime.now()) ? null : () => setState(() => _day = _day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      children: [
        if (items.isEmpty) EmptyState(compact: true, icon: Icons.timeline, title: l.healthNothingRecorded, message: l.healthTimelineEmptyMessage),
        for (final (_, w) in items) w,
        const SizedBox(height: Space.m),
        Text(l.healthTimelineFooter, style: context.text.bodySmall),
      ],
    );
  }
}

String _contextLabel(AppLocalizations l, GlucoseContext c) => switch (c) {
      GlucoseContext.fasting => l.healthContextFasting,
      GlucoseContext.beforeMeal => l.healthContextBeforeMeal,
      GlucoseContext.afterMeal => l.healthContextAfterMeal,
      GlucoseContext.bedtime => l.healthContextBedtime,
      GlucoseContext.other => l.healthContextOther,
    };

/// Locale-aware decimal ("5.4" in English, "5,4" in French).
String _decimal(BuildContext context, double v, int digits) =>
    NumberFormat.decimalPatternDigits(locale: localeTag(context), decimalDigits: digits).format(v);

/// A glucose value with its unit; mmol/L keeps one decimal, mg/dL none.
String _reading(BuildContext context, double v, GlucoseUnit unit, {int? digits}) =>
    '${_decimal(context, v, digits ?? (unit == GlucoseUnit.mmolL ? 1 : 0))}${localeTag(context).startsWith('fr') ? '\u00a0' : ' '}${context.labelOf(unit)}';
