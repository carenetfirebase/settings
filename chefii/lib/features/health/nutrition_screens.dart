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
  if (!ok && context.mounted) showMessage(context, 'Couldn\'t open the link.', error: true);
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
    final nutrients = [
      if (wellness.calorieTracking) Nutrient.energyKcal,
      Nutrient.protein, Nutrient.carbohydrate, Nutrient.fat, Nutrient.fibre, Nutrient.sodium, Nutrient.sugars, Nutrient.saturatedFat,
    ];
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Nutrition',
        title: 'Your nutrition',
        subtitle: stats.loggedDays == 0 ? null : 'Daily average across ${stats.loggedDays} logged day${stats.loggedDays == 1 ? '' : 's'}',
      ),
      actions: [IconButton(tooltip: 'Insights', onPressed: () => context.push('/you/nutrition/intelligence'), icon: const Icon(Icons.lightbulb_outline))],
      children: [
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 1, label: Text('Today')), ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days'))],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        const SizedBox(height: Space.m),
        if (stats.loggedDays == 0)
          EmptyState(icon: Icons.insights_outlined, title: 'No meals logged yet', message: 'Cook with Chefii or log meals in your journal to see estimates here.', actionLabel: 'Log a meal', onAction: () => context.push('/journal/add'))
        else ...[
          for (final n in nutrients)
            _NutrientBar(nutrient: n, value: stats.avg[n], onTap: () => context.push('/you/nutrition/nutrient/${n.name}')),
          const SizedBox(height: Space.m),
          Text(
            'Estimates from recipes and reference data. ${stats.completeness < 0.9 ? 'Some meals had no nutrition data (${((1 - stats.completeness) * 100).round()}%), so totals are likely low. ' : ''}'
            'Daily Values are Health Canada\'s label reference — a yardstick, not a personal target.',
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
    return Semantics(
      button: onTap != null,
      label: '${nutrient.label}: about ${formatNutrient(nutrient, value)}${pct == null ? '' : ', ${(pct * 100).round()} percent of the Daily Value'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.m),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(nutrient.label, style: context.text.titleSmall)),
              Text('≈ ${formatNutrient(nutrient, value)}', style: context.text.titleSmall),
              if (pct != null) Text('  ${(pct * 100).round()}% DV', style: context.text.bodySmall),
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
    final fibreLow = now.loggedDays > 0 && now.avg[Nutrient.fibre] < 20;
    final highFibre = ref.watch(rankedRecipesProvider((mealType: null, maxMinutes: null, tag: null)))
        .where((a) => a.recipe.nutritionPerServing[Nutrient.fibre] >= 8)
        .take(3)
        .toList();

    String trend(Nutrient n) {
      if (before.loggedDays == 0 || now.loggedDays == 0) return 'Not enough history yet';
      final a = now.avg[n], b = before.avg[n];
      if (b == 0) return '≈ ${formatNutrient(n, a)} a day';
      final change = (a - b) / b;
      if (change.abs() < 0.1) return 'Steady at ≈ ${formatNutrient(n, a)} a day';
      return '${change > 0 ? 'Up' : 'Down'} ${(change.abs() * 100).round()}% vs the week before';
    }

    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Nutrition', title: 'Insights', subtitle: 'Patterns from your journal, explained with evidence.'),
      actions: [IconButton(tooltip: 'Evidence library', onPressed: () => context.push('/you/nutrition/evidence'), icon: const Icon(Icons.library_books_outlined))],
      children: [
        if (now.loggedDays == 0)
          const EmptyState(compact: true, icon: Icons.insights_outlined, title: 'Insights need a few days of meals', message: 'Keep cooking and logging — we\'ll look for patterns after a few days.'),
        const SectionHeader('Trends', topSpacing: 0),
        for (final n in [Nutrient.fibre, Nutrient.protein, Nutrient.sodium, Nutrient.sugars])
          ListTile(contentPadding: EdgeInsets.zero, title: Text(n.label), subtitle: Text(trend(n)), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/nutrient/${n.name}')),
        const SectionHeader('Variety this week'),
        Row(children: [
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$variety', style: context.metric), Text('different meals', style: context.text.bodySmall)]))),
          const SizedBox(width: Space.xs),
          Expanded(child: SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${plants.length}', style: context.metric), Text('plant foods in Chefii recipes', style: context.text.bodySmall)]))),
        ]),
        if (fibreLow) ...[
          const SectionHeader('Something to try'),
          EvidenceReferenceCard(
            claim: claimById('fibre_foods')!,
            sources: [for (final s in claimById('fibre_foods')!.sourceIds) evidenceSources[s]!],
            onTap: () => context.push('/you/nutrition/evidence?claim=fibre_foods'),
          ),
          const SizedBox(height: Space.s),
          for (final a in highFibre)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(a.recipe.title),
                subtitle: Text('≈ ${a.recipe.nutritionPerServing[Nutrient.fibre].round()} g fibre per serving · ${a.label}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/recipe/${a.recipe.id}'),
              ),
            ),
        ],
        const SectionHeader('More to explore'),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.spa_outlined), title: const Text('Hair, skin & nails'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/nutrition/hair-skin-nails')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.sentiment_satisfied_alt_outlined), title: const Text('Smile & Food'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/you/smile')),
        const SizedBox(height: Space.m),
        Text('Chefii provides general nutrition education, not medical advice. For personal guidance, talk to a registered dietitian.', style: context.text.bodySmall),
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
    final claims = evidenceClaims.where((c) => c.topic == 'Hair, skin & nails').toList();
    return PremiumAppScaffold(
      header: const EditorialPageHeader(eyebrow: 'Nutrition', title: 'Hair, skin & nails', subtitle: 'A private notebook, plus what the evidence does — and doesn\'t — say.'),
      children: [
        SoftCard(
          color: context.palette.infoSoft,
          child: Text(
            'Changes in hair, skin and nails have many causes besides diet — hormones, thyroid, stress, medications, skin conditions and genetics. '
            'Sudden hair loss, rashes, or nail changes that don\'t settle are worth seeing a doctor, dermatologist or pharmacist about.',
            style: context.text.bodySmall?.copyWith(color: context.palette.ink),
          ),
        ),
        const SectionHeader('Note a concern'),
        Wrap(spacing: Space.xs, children: [
          for (final a in [ConcernArea.hair, ConcernArea.skin, ConcernArea.nails, ConcernArea.energy, ConcernArea.other])
            ChoiceChip(label: Text(a.name[0].toUpperCase() + a.name.substring(1)), selected: _area == a, onSelected: (_) => setState(() => _area = a)),
        ]),
        const SizedBox(height: Space.s),
        TextField(controller: _text, maxLines: 2, decoration: const InputDecoration(hintText: 'What have you noticed?')),
        const SizedBox(height: Space.xs),
        Text('How much is it bothering you? ($_severity of 5)', style: context.text.bodySmall),
        Slider(value: _severity.toDouble(), min: 1, max: 5, divisions: 4, label: '$_severity', onChanged: (v) => setState(() => _severity = v.round())),
        SecondaryActionButton(
          label: 'Save note',
          onPressed: () async {
            if (_text.text.trim().isEmpty) return;
            await ref.read(healthRepoProvider).addConcern(ref.read(uidProvider)!, _area, _text.text.trim(), _severity);
            _text.clear();
            if (context.mounted) showMessage(context, 'Saved privately');
          },
        ),
        if (concerns.isNotEmpty) ...[
          const SectionHeader('Your notes'),
          for (final c in concerns)
            Card(
              margin: const EdgeInsets.only(bottom: Space.xs),
              child: ListTile(
                title: Text(c.description),
                subtitle: Text('${c.area.name} · ${formatDay(c.recordedAt)} · ${c.severity}/5'),
                trailing: IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => ref.read(healthRepoProvider).deleteConcern(c.uid, c.id)),
              ),
            ),
        ],
        const SectionHeader('What the evidence says'),
        for (final c in claims)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: EvidenceReferenceCard(claim: c, sources: [for (final s in c.sourceIds) evidenceSources[s]!], onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
          ),
        const SizedBox(height: Space.s),
        SecondaryActionButton(icon: Icons.group_add_outlined, label: 'Share with a dietitian', onPressed: () => context.push('/you/circle')),
      ],
    );
  }
}

// ---------------------------------------------------------------- 63 Scientific evidence

class EvidenceScreen extends StatelessWidget {
  const EvidenceScreen({super.key, this.claimId});
  final String? claimId;

  @override
  Widget build(BuildContext context) {
    final focus = claimId == null ? null : claimById(claimId!);
    final claims = focus == null ? evidenceClaims : [focus];
    return PremiumAppScaffold(
      header: EditorialPageHeader(
        eyebrow: 'Evidence',
        title: focus?.topic ?? 'How we know',
        subtitle: focus == null ? 'Every nutrition statement in Chefii, its sources and its limits.' : null,
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
                _kv(context, 'Evidence', c.strength.label),
                _kv(context, 'Review', c.professionallyReviewed ? 'Professionally reviewed ${c.reviewedOn.toIso()}' : 'Internal summary (${c.reviewedOn.toIso()}), awaiting professional review'),
                _kv(context, 'Limitations', c.limitations),
                if (c.foodSources.isNotEmpty)
                  _kv(context, 'Foods', c.foodSources.map((id) => catalogById[id]?.product.name).whereType<String>().join(', ')),
                const SizedBox(height: Space.xs),
                if (c.sourceIds.isEmpty) Text('Source: citation pending review.', style: context.text.bodySmall),
                for (final id in c.sourceIds)
                  Builder(builder: (context) {
                    final s = evidenceSources[id]!;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined),
                      title: Text(s.title),
                      subtitle: Text('${s.publisher} · ${s.studyType.label} · ${s.year}'),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => openSource(context, s.url),
                    );
                  }),
              ]),
            ),
          ),
        Text('Method: we prefer national guidelines and systematic reviews; single studies are not used for recommendations.', style: context.text.bodySmall),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: context.palette.ink)),
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
    return PremiumAppScaffold(
      header: EditorialPageHeader(eyebrow: 'Nutrient', title: nutrient.label),
      children: [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stats.loggedDays == 0 ? 'No data yet' : '≈ ${formatNutrient(nutrient, stats.avg[nutrient])} a day', style: context.text.headlineMedium),
            Text(stats.loggedDays == 0 ? 'Log meals to see an estimate.' : 'Average over ${stats.loggedDays} logged day${stats.loggedDays == 1 ? '' : 's'} this week', style: context.text.bodySmall),
            if (dv != null) ...[
              const SizedBox(height: Space.s),
              Text('Reference: ${formatNutrient(nutrient, dv.amount)} (${dv.kind}, ${dv.source})', style: context.text.bodySmall),
            ],
            const SizedBox(height: Space.xs),
            Text('Data completeness: ${(stats.completeness * 100).round()}% of meals had nutrition estimates.', style: context.text.bodySmall),
          ]),
        ),
        if (topMeals.isNotEmpty && topMeals.first.nutrition[nutrient] > 0) ...[
          const SectionHeader('Biggest contributors this week'),
          for (final m in topMeals.take(3))
            ListTile(contentPadding: EdgeInsets.zero, title: Text(m.title), trailing: Text(formatNutrient(nutrient, m.nutrition[nutrient]))),
        ],
        const SectionHeader('Rich sources'),
        for (final e in top.take(6))
          ListTile(contentPadding: EdgeInsets.zero, title: Text(e.product.name), trailing: Text('${formatNutrient(nutrient, e.reference.per100g[nutrient])} / 100 g')),
        if (claims.isNotEmpty) ...[
          const SectionHeader('Evidence'),
          for (final c in claims)
            EvidenceReferenceCard(claim: c, sources: [for (final s in c.sourceIds) evidenceSources[s]!], onTap: () => context.push('/you/nutrition/evidence?claim=${c.id}')),
        ],
        const SizedBox(height: Space.m),
        Text('Individual needs vary. Estimates can\'t account for exact brands, portions, or added salt.', style: context.text.bodySmall),
      ],
    );
  }
}
