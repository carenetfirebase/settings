import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../domain/catalog/catalog.dart';
import '../../domain/models/health.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/nutrition.dart';
import '../../domain/models/profile.dart';
import '../../domain/nutrition/evidence_library.dart';
import '../../domain/nutrition/evidence_library_fr.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../journal/journal_screens.dart';
import '../shared/recipe_logic.dart';

/// Daily averages over [days] using only days that have records.
({NutrientProfile avg, int loggedDays, double completeness}) dailyAverage(List<MealConsumption> meals, int days) {
  final byDay = <String, List<MealConsumption>>{};
  for (final m in meals) {
    final l = m.eatenAt.toLocal();
    byDay.putIfAbsent('${l.year}-${l.month}-${l.day}', () => []).add(m);
  }
  if (byDay.isEmpty) return (avg: NutrientProfile.empty, loggedDays: 0, completeness: 0);
  final total = sumNutrition(meals);
  final withData = meals.where((m) => m.nutrition.completeness > 0).length;
  return (avg: total.scale(1 / byDay.length), loggedDays: byDay.length, completeness: withData / meals.length);
}

Future<void> openSource(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, context.l10n.healthOpenLinkError, error: true);
}

// ---------------------------------------------------------------- 50 Nutrition dashboard

class NutritionDashboardScreen extends ConsumerStatefulWidget {
  const NutritionDashboardScreen({super.key});

  @override
  ConsumerState<NutritionDashboardScreen> createState() => _NutritionDashboardScreenState();
}

class _NutritionDashboardScreenState extends ConsumerState<NutritionDashboardScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(journalProvider(lastDays(_days))).value ?? const <MealConsumption>[];
    final wellness = ref.watch(wellnessProvider).value ?? const WellnessPreferences();
    final stats = dailyAverage(meals, _days);
    final l = context.l10n;
    final nutrients = [
      if (wellness.calorieTracking) Nutrient.energyKcal,
      Nutrient.protein, Nutrient.carbohydrate, Nutrient.fat, Nutrient.fibre, Nutrient.sodium, Nutrient.sugars, Nutrient.saturatedFat,
    ];
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l.healthNutritionEyebrow,
        title: l.healthYourNutrition,
        subtitle: stats.loggedDays == 0 ? null : l.healthDailyAverageSubtitle(stats.loggedDays),
      ),
      actions: [IconButton(tooltip: l.healthInsights, onPressed: () => context.push('/you/nutrition/intelligence'), icon: const Icon(Icons.lightbulb_outline))],
      children: [
        SegmentedButton<int>(
          segments: [ButtonSegment(value: 1, label: Text(l.commonToday)), ButtonSegment(value: 7, label: Text(l.healthDaysSegment(7))), ButtonSegment(value: 30, label: Text(l.healthDaysSegment(30)))],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        const SizedBox(height: Space.m),
        if (stats.loggedDays == 0)
          EmptyState(icon: Icons.insights_outlined, title: l.healthNoMealsTitle, message: l.healthNoMealsMessage, actionLabel: l.healthLogMeal, onAction: () => context.push('/journal/add'))
        else ...[
          for (final n in nutrients)
            _NutrientBar(nutrient: n, value: stats.avg[n], onTap: () => context.push('/you/nutrition/nutrient/${n.name}')),
          const SizedBox(height: Space.m),
          Text(
            [
              l.healthEstimatesNote,
              if (stats.completeness < 0.9) l.healthMissingDataNote(((1 - stats.completeness) * 100).round()),
              l.healthDailyValueNote,
            ].join(' '),
            style: context.text.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _NutrientBar extends StatelessWidget {
  const _NutrientBar({required this.nutrient, required this.value, this.onTap});
  final Nutrient nutrient;
  final double value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dv = dailyReferences[nutrient];
    final pct = dv == null ? null : value / dv.amount;
    final l = context.l10n;
    final name = context.labelOf(nutrient);
    final amount = formatNutrient(nutrient, value);
    return Semantics(
      button: onTap != null,
      label: pct == null ? l.healthNutrientBarSemantics(name, amount) : l.healthNutrientBarSemanticsDv(name, amount, (pct * 100).round()),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.m),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: context.text.titleSmall)),
              Text('≈ $amount', style: context.text.titleSmall), // l10n-ignore: symbol + formatted amount
              if (pct != null) Text('  ${l.healthPercentDv((pct * 100).round())}', style: context.text.bodySmall), // l10n-ignore: only translated values
            ]),
            if (pct != null) ...[
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct.clamp(0, 1), minHeight: 6)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 61 Nutrition intelligence

class NutritionIntelligenceScreen extends ConsumerWidget {
  const NutritionIntelligenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(journalProvider(lastDays(7))).value ?? const <MealConsumption>[];
    final all14 = ref.watch(journalProvider(lastDays(14))).value ?? const <MealConsumption>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toUtc();
    final previous = all14.where((m) => m.eatenAt.isBefore(cutoff)).toList();
    final now = dailyAverage(recent, 7);
    final before = dailyAverage(previous, 7);
    final variety = {for (final m in recent) m.recipeId ?? m.title.toLowerCase()}.length;
    final plants = <String>{};
    final recipes = ref.watch(allRecipesProvider);
    for (final m in recent) {
      final r = recipes.where((r) => r.id == m.recipeId).firstOrNull;
      for (final i in r?.ingredients ?? const []) {
        final cat = catalogById[i.productId]?.product.category.name;
        if (cat == 'produce' || i.productId == 'lentils' || i.productId == 'chickpeas' || i.productId == 'black_beans' || i.productId == 'quinoa' || i.productId == 'oats') {
          plants.add(i.productId!);
        }
      }
    }
    final french = ref.watch(frenchContentProvider);
    final fibreLow = now.loggedDays > 0 && now.avg[Nutrient.fibre] < 20;
    final highFibre = ref.watch(rankedRecipesProvider((mealType: null, maxMinutes: null, tag: null)))
        .where((a) => a.recipe.nutritionPerServing[Nutrient.fibre] >= 8)
        .take(3)
        .toList();
    final l = context.l10n;

    String trend(Nutrient n) {
      if (before.loggedDays == 0 || now.loggedDays == 0) return l.healthNotEnoughHistory;
      final a = now.avg[n], b = before.avg[n];
      if (b == 0) return l.healthPerDay(formatNutrient(n, a));
      final change = (a - b) / b;
      if (change.abs() < 0.1) return l.healthSteadyAt(formatNutrient(n, a));
      final pct = (change.abs() * 100).round();
      return change > 0 ? l.healthTrendUp(pct) : l.healthTrendDown(pct);
    }

    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthNutritionEyebrow, title: l.healthInsights, subtitle: l.healthInsightsSubtitle),
      actions: [IconButton(tooltip: l.healthEvidenceLibrary, onPressed: () => context.push('/you/nutrition/evidence'), icon: const Icon(Icons.library_books_outlined))],
      children: [
        if (now.loggedDays == 0)
          EmptyState(compact: true, icon: Icons.insights_outlined, title: l.healthInsightsEmptyTitle, message: l.healthInsightsEmptyMessage),
        SectionHeader(l.healthTrends, topSpacing: 0),
        for (final n in [Nutrient.fibre, Nutrient.protein, Nutrient.sodium, Nutrient.sugars])
          ListTile(contentPadding: EdgeInsets.zero, title: Text(context.labelOf(n)), subtitle: Text(trend(n)), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/nutrient/${n.name}')),
        SectionHeader(l.healthVarietyThisWeek),
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$variety', style: context.metric), Text(l.healthDifferentMeals(variety), style: context.text.bodySmall)]))), // l10n-ignore: only translated values
          const SizedBox(width: Space.xs),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${plants.length}', style: context.metric), Text(l.healthPlantFoods(plants.length), style: context.text.bodySmall)]))), // l10n-ignore: only translated values
        ]),
        if (fibreLow) ...[
          SectionHeader(l.healthSomethingToTry),
          EvidenceReferenceCard(
            claim: localizeClaim(claimById('fibre_foods')!, french),
            sources: localizedSourcesOf(claimById('fibre_foods')!, french),
            onTap: () => context.push('/you/nutrition/evidence?claim=fibre_foods'),
          ),
          const SizedBox(height: Space.s),
          for (final a in highFibre)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(a.recipe.title),
                subtitle: Text('${l.healthFibrePerServing(a.recipe.nutritionPerServing[Nutrient.fibre].round())} · ${l.healthAvailabilityLabel(a.missing.length)}'), // l10n-ignore: only translated values
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/recipe/${a.recipe.id}'),
              ),
            ),
        ],
        SectionHeader(l.healthMoreToExplore),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.spa_outlined), title: Text(l.healthHairSkinNails), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/hair-skin-nails')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.sentiment_satisfied_alt_outlined), title: Text(l.healthSmileAndFood), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/smile')),
        const SizedBox(height: Space.m),
        Text(l.healthEducationDisclaimer, style: context.text.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- 62 Hair, skin & nails

class HairSkinNailsScreen extends ConsumerStatefulWidget {
  const HairSkinNailsScreen({super.key});

  @override
  ConsumerState<HairSkinNailsScreen> createState() => _HairSkinNailsScreenState();
}

class _HairSkinNailsScreenState extends ConsumerState<HairSkinNailsScreen> {
  ConcernArea _area = ConcernArea.hair;
  final _text = TextEditingController();
  int _severity = 2;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final concerns = ref.watch(concernsProvider).value ?? const <UserConcern>[];
    final french = ref.watch(frenchContentProvider);
    final claims = evidenceClaims.where((c) => c.topic == 'Hair, skin & nails').toList(); // l10n-ignore: content topic key (English); translated at display
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthNutritionEyebrow, title: l.healthHairSkinNails, subtitle: l.healthHairSubtitle),
      children: [
        SoftCard(
          color: context.palette.infoSoft,
          child: Text(
            l.healthHairCausesNote,
            style: context.text.bodySmall?.copyWith(color: context.palette.ink),
          ),
        ),
        SectionHeader(l.healthNoteAConcern),
        Wrap(spacing: Space.xs, children: [
          for (final a in [ConcernArea.hair, ConcernArea.skin, ConcernArea.nails, ConcernArea.energy, ConcernArea.other])
            ChoiceChip(label: Text(_concernLabel(l, a)), selected: _area == a, onSelected: (_) => setState(() => _area = a)),
        ]),
        const SizedBox(height: Space.s),
        TextField(controller: _text, maxLines: 2, decoration: InputDecoration(hintText: l.healthWhatHaveYouNoticed)),
        const SizedBox(height: Space.xs),
        Text(l.healthBotherLevel(_severity), style: context.text.bodySmall),
        Semantics(label: l.healthBotherSemantics, child: Slider(value: _severity.toDouble(), min: 1, max: 5, divisions: 4, label: '$_severity', onChanged: (v) => setState(() => _severity = v.round()))), // l10n-ignore: number
        SecondaryActionButton(
          label: l.healthSaveNote,
          onPressed: () async {
            if (_text.text.trim().isEmpty) return;
            await ref.read(healthRepoProvider).addConcern(ref.read(uidProvider)!, _area, _text.text.trim(), _severity);
            _text.clear();
            if (context.mounted) showMessage(context, l.healthSavedPrivately);
          },
        ),
        if (concerns.isNotEmpty) ...[
          SectionHeader(l.healthYourNotes),
          for (final c in concerns)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(c.description),
                subtitle: Text('${_concernLabel(l, c.area).toLowerCase()} · ${formatDay(context, c.recordedAt)} · ${c.severity}/5'), // l10n-ignore: only translated values
                trailing: IconButton(tooltip: l.healthDelete, icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(healthRepoProvider).deleteConcern(c.uid, c.id)),
              ),
            ),
        ],
        SectionHeader(l.healthWhatEvidenceSays),
        for (final c in claims)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: EvidenceReferenceCard(claim: localizeClaim(c, french), sources: localizedSourcesOf(c, french), onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
          ),
        const SizedBox(height: Space.s),
        SecondaryActionButton(icon: Icons.group_add_outlined, label: l.healthShareWithDietitian, onPressed: () => context.push('/you/circle')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 63 Scientific evidence

class EvidenceScreen extends ConsumerWidget {
  const EvidenceScreen({super.key, this.claimId});
  final String? claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final french = ref.watch(frenchContentProvider);
    final english = claimId == null ? null : claimById(claimId!);
    final focus = english == null ? null : localizeClaim(english, french);
    final claims = focus == null ? [for (final c in evidenceClaims) localizeClaim(c, french)] : [focus];
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: l.healthEvidence,
        title: focus?.topic ?? l.healthHowWeKnow,
        subtitle: focus == null ? l.healthEvidenceSubtitle : null,
      ),
      children: [
        for (final c in claims)
          Card(
            margin: const EdgeInsets.only(bottom: Space.m),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.topic.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.palette.accent)),
                const SizedBox(height: Space.xs),
                Text(c.statement, style: context.text.titleMedium),
                const SizedBox(height: Space.s),
                _kv(context, l.healthEvidence, context.labelOf(c.strength)),
                _kv(context, l.healthReview, c.professionallyReviewed ? l.healthProfessionallyReviewed(c.reviewedOn.toIso()) : l.healthInternalSummary(c.reviewedOn.toIso())),
                _kv(context, l.healthLimitations, c.limitations),
                if (c.foodSources.isNotEmpty)
                  _kv(context, l.healthFoods, c.foodSources.where(catalogById.containsKey).map((id) => context.productName(id, catalogById[id]!.product.name)).join(', ')),
                const SizedBox(height: Space.xs),
                if (c.sourceIds.isEmpty) Text(l.healthCitationPending, style: context.text.bodySmall),
                for (final id in c.sourceIds)
                  Builder(builder: (context) {
                    final s = localizeSource(evidenceSources[id]!, french);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined),
                      title: Text(s.title),
                      subtitle: Text('${s.publisher} · ${context.labelOf(s.studyType)} · ${s.year}'), // l10n-ignore: content + translated label
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => openSource(context, s.url),
                    );
                  }),
              ]),
            ),
          ),
        Text(l.healthMethodNote, style: context.text.bodySmall),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '${context.l10n.healthLabelColon(k)} ', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: context.palette.ink)),
          TextSpan(text: v, style: context.text.bodySmall),
        ])),
      );
}

// ---------------------------------------------------------------- 64 Nutrient detail

class NutrientDetailScreen extends ConsumerWidget {
  const NutrientDetailScreen({super.key, required this.nutrient});
  final Nutrient nutrient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(journalProvider(lastDays(7))).value ?? const <MealConsumption>[];
    final stats = dailyAverage(meals, 7);
    final dv = dailyReferences[nutrient];
    final top = [...catalog]..sort((a, b) => b.reference.per100g[nutrient].compareTo(a.reference.per100g[nutrient]));
    final claims = (claimsByNutrient[nutrient] ?? const []).map(claimById).whereType<EvidenceClaim>().toList();
    final topMeals = [...meals]..sort((a, b) => b.nutrition[nutrient].compareTo(a.nutrition[nutrient]));
    final french = ref.watch(frenchContentProvider);
    final l = context.l10n;
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: l.healthNutrientEyebrow, title: context.labelOf(nutrient)),
      children: [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stats.loggedDays == 0 ? l.healthNoDataYet : l.healthPerDay(formatNutrient(nutrient, stats.avg[nutrient])), style: context.text.headlineMedium),
            Text(stats.loggedDays == 0 ? l.healthLogMealsForEstimate : l.healthAverageThisWeek(stats.loggedDays), style: context.text.bodySmall),
            if (dv != null) ...[
              const SizedBox(height: Space.s),
              Text(_referenceLine(l, nutrient, dv, french), style: context.text.bodySmall),
            ],
            const SizedBox(height: Space.xs),
            Text(l.healthDataCompleteness((stats.completeness * 100).round()), style: context.text.bodySmall),
          ]),
        ),
        if (topMeals.isNotEmpty && topMeals.first.nutrition[nutrient] > 0) ...[
          SectionHeader(l.healthBiggestContributors),
          for (final m in topMeals.take(3))
            ListTile(contentPadding: EdgeInsets.zero, title: Text(m.title), trailing: Text(formatNutrient(nutrient, m.nutrition[nutrient]))),
        ],
        SectionHeader(l.healthRichSources),
        for (final e in top.take(6))
          ListTile(contentPadding: EdgeInsets.zero, title: Text(context.productName(e.product.id, e.product.name)), trailing: Text(l.healthPer100g(formatNutrient(nutrient, e.reference.per100g[nutrient])))),
        if (claims.isNotEmpty) ...[
          SectionHeader(l.healthEvidence),
          for (final c in claims)
            EvidenceReferenceCard(claim: localizeClaim(c, french), sources: localizedSourcesOf(c, french), onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
        ],
        const SizedBox(height: Space.m),
        Text(l.healthIndividualNeeds, style: context.text.bodySmall),
      ],
    );
  }
}

String _concernLabel(AppLocalizations l, ConcernArea a) => switch (a) {
      ConcernArea.hair => l.healthConcernHair,
      ConcernArea.skin => l.healthConcernSkin,
      ConcernArea.nails => l.healthConcernNails,
      ConcernArea.energy => l.healthConcernEnergy,
      ConcernArea.digestion => l.healthConcernDigestion,
      ConcernArea.other => l.healthConcernOther,
    };

/// Every reference in [dailyReferences] today is a Health Canada label Daily
/// Value; anything else shows its kind and source, translated when [french].
String _referenceLine(AppLocalizations l, Nutrient n, DailyReference dv, bool french) {
  final amount = formatNutrient(n, dv.amount);
  if (dv.kind == 'Daily Value' && dv.source == 'Health Canada, Table of Daily Values') return l.healthReferenceDailyValue(amount); // l10n-ignore
  return l.healthReferenceOther(amount, localizeReferenceTerm(dv.kind, french), localizeReferenceTerm(dv.source, french));
}
