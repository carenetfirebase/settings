import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../domain/models/codec.dart';
import '../../../domain/models/inventory.dart';
import '../../../domain/models/nutrition.dart';
import '../../../domain/models/planning.dart';
import '../../../domain/models/recipe.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/labels.dart';
import '../../format.dart';
import '../theme.dart';
import '../tokens.dart';

/// Editorial still-life illustration for a recipe or ingredient.
///
/// Deliberately an illustration, never a photo: Chefii does not present
/// generated imagery as a picture of the user's food. Swap for licensed
/// photography by key when available (see docs/DECISIONS.md).
class FoodArtwork extends StatelessWidget {
  const FoodArtwork({super.key, required this.artKey, this.height = 180, this.radius = Radii.l, this.label});

  final String? artKey;
  final double height;
  final double radius;
  final String? label;

  static const palettes = <String, List<Color>>{
    'tomato': [Color(0xFFE9D6C6), Color(0xFFC2533F), Color(0xFF6E8A5A), Color(0xFFF3E7DA)],
    'citrus': [Color(0xFFEFE8D4), Color(0xFFE2B84E), Color(0xFF8DA584), Color(0xFFFBF5E6)],
    'herb': [Color(0xFFE3E8D7), Color(0xFF5E7B55), Color(0xFFB8C7A2), Color(0xFFF6F7EF)],
    'berry': [Color(0xFFE9E1E8), Color(0xFF4F4A7C), Color(0xFFB4677A), Color(0xFFF7F2F5)],
    'butter': [Color(0xFFF2EAD6), Color(0xFFE7C66B), Color(0xFFB69B72), Color(0xFFFCF7EA)],
    'spice': [Color(0xFFEFDFC9), Color(0xFFC37A35), Color(0xFF8E3B2E), Color(0xFFF9EFE2)],
    'avocado': [Color(0xFFE5EAD6), Color(0xFF7E9A4C), Color(0xFF3F5233), Color(0xFFF5F7EC)],
    'roast': [Color(0xFFEEDFD0), Color(0xFFB8693C), Color(0xFF7C5236), Color(0xFFF8EFE5)],
    'ginger': [Color(0xFFF0E5CF), Color(0xFFD9A441), Color(0xFF344439), Color(0xFFFAF4E6)],
    'earth': [Color(0xFFE7E1D6), Color(0xFF8C7A62), Color(0xFF4F5A47), Color(0xFFF6F2EA)],
    'cream': [Color(0xFFF1EEE6), Color(0xFFD9CDB7), Color(0xFFB69B72), Color(0xFFFFFDF9)],
    'orchard': [Color(0xFFEDE4D8), Color(0xFFC0473B), Color(0xFF8BA25A), Color(0xFFF9F2E8)],
  };

  static String keyFor(String text) {
    final keys = palettes.keys.toList();
    return keys[text.codeUnits.fold<int>(0, (a, b) => a + b) % keys.length];
  }

  @override
  Widget build(BuildContext context) {
    final key = artKey != null && palettes.containsKey(artKey) ? artKey! : keyFor(label ?? 'chefii');
    return Semantics(
      image: true,
      label: label == null ? context.l10n.coreIllustration : context.l10n.coreIllustrationFor(label!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Theme.of(context).brightness == Brightness.dark
              // Evening light: dim the cream backgrounds so they don't glare in dark mode.
              ? ColorFiltered(
                  colorFilter: const ColorFilter.mode(Color(0xFFC6C2B8), BlendMode.modulate),
                  child: CustomPaint(painter: _StillLifePainter(palettes[key]!, seed: (label ?? key).hashCode)),
                )
              : CustomPaint(painter: _StillLifePainter(palettes[key]!, seed: (label ?? key).hashCode)),
        ),
      ),
    );
  }
}

class _StillLifePainter extends CustomPainter {
  _StillLifePainter(this.c, {required this.seed});
  final List<Color> c;
  final int seed;

  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(seed);
    canvas.drawRect(Offset.zero & s, Paint()..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c[3], c[0]],
    ).createShader(Offset.zero & s));
    // Linen table edge.
    canvas.drawRect(Rect.fromLTWH(0, s.height * 0.72, s.width, s.height * 0.28), Paint()..color = c[0].withValues(alpha: 0.9));
    // Plate.
    final plateCenter = Offset(s.width * (0.42 + r.nextDouble() * 0.12), s.height * 0.62);
    final plateR = math.min(s.width, s.height) * 0.36;
    canvas.drawOval(Rect.fromCenter(center: plateCenter.translate(6, 10), width: plateR * 2.1, height: plateR * 1.15),
        Paint()..color = Colors.black.withValues(alpha: 0.06));
    canvas.drawOval(Rect.fromCenter(center: plateCenter, width: plateR * 2.1, height: plateR * 1.1), Paint()..color = c[3]);
    canvas.drawOval(Rect.fromCenter(center: plateCenter, width: plateR * 1.5, height: plateR * 0.78),
        Paint()..color = c[0].withValues(alpha: 0.6));
    // Food forms.
    for (var i = 0; i < 5; i++) {
      final o = plateCenter.translate((r.nextDouble() - 0.5) * plateR * 1.1, (r.nextDouble() - 0.5) * plateR * 0.45);
      final rad = plateR * (0.14 + r.nextDouble() * 0.16);
      canvas.drawCircle(o, rad, Paint()..color = (i.isEven ? c[1] : c[2]).withValues(alpha: 0.85));
    }
    // Leaves.
    final leaf = Paint()..color = c[2].withValues(alpha: 0.9);
    for (var i = 0; i < 3; i++) {
      final o = plateCenter.translate((r.nextDouble() - 0.5) * plateR, -plateR * 0.12 + r.nextDouble() * 10);
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(r.nextDouble() * math.pi);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: plateR * 0.32, height: plateR * 0.12), leaf);
      canvas.restore();
    }
    // A small bowl and a sprig in the corner.
    final bowl = Offset(s.width * 0.86, s.height * 0.3);
    canvas.drawCircle(bowl, plateR * 0.32, Paint()..color = c[3]);
    canvas.drawCircle(bowl, plateR * 0.22, Paint()..color = c[1].withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _StillLifePainter old) => old.seed != seed || old.c != c;
}

/// Status with icon + text + colour (never colour alone).
class InventoryStatusBadge extends StatelessWidget {
  const InventoryStatusBadge({super.key, required this.status, this.compact = false});

  final InventoryStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData icon, Color fg, Color bg) = switch (status) {
      InventoryStatus.confirmed => (Icons.check_circle_outline, p.success, p.successSoft),
      InventoryStatus.estimated => (Icons.blur_on, p.info, p.infoSoft),
      InventoryStatus.needsReview => (Icons.help_outline, p.warning, p.warningSoft),
      InventoryStatus.depleted => (Icons.remove_circle_outline, p.muted, p.hairline),
      InventoryStatus.pastRecordedDate => (Icons.event_busy_outlined, p.error, p.errorSoft),
    };
    return Semantics(
      label: context.l10n.coreStatus(context.labelOf(status)),
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : Space.xs, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              if (!compact) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(context.labelOf(status), overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: fg, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TagPill extends StatelessWidget {
  const TagPill(this.label, {super.key, this.icon, this.color, this.background});
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
      decoration: BoxDecoration(color: background ?? p.surfaceSoft, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color ?? p.ink), const SizedBox(width: 4)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: color ?? p.ink, fontSize: 12))),
        ],
      ),
    );
  }
}

class LuxuryRecipeCard extends StatelessWidget {
  const LuxuryRecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.availabilityLabel,
    this.canCookNow = false,
    this.rationale,
    this.showNutrition = true,
    this.compact = false,
    this.trailing,
  });

  final Recipe recipe;
  final VoidCallback? onTap;
  final String? availabilityLabel;
  final bool canCookNow;
  final String? rationale;
  final bool showNutrition;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kcal = recipe.nutritionPerServing[Nutrient.energyKcal];
    final l = context.l10n;
    final semantics = [
      recipe.title,
      l.coreMinutesSpoken(recipe.totalMinutes),
      context.labelOf(recipe.difficulty),
      ?availabilityLabel,
    ].join(', ');
    return Semantics(
      button: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodArtwork(artKey: recipe.imageKey, height: compact ? 120 : 172, radius: 0, label: recipe.title),
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.cuisine.toUpperCase(), style: context.text.labelSmall?.copyWith(color: p.accent)),
                    const SizedBox(height: Space.xxs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(recipe.title, style: compact ? context.text.headlineSmall : context.text.headlineMedium,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        ?trailing,
                      ],
                    ),
                    if (rationale != null && rationale!.isNotEmpty) ...[
                      const SizedBox(height: Space.xxs),
                      Text(rationale!, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: Space.s),
                    Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        TagPill(l.coreMinutesShort(recipe.totalMinutes), icon: Icons.schedule),
                        TagPill(context.labelOf(recipe.difficulty), icon: Icons.restaurant),
                        if (availabilityLabel != null)
                          TagPill(
                            availabilityLabel!,
                            icon: canCookNow ? Icons.check : Icons.shopping_basket_outlined,
                            color: canCookNow ? p.success : p.ink,
                            background: canCookNow ? p.successSoft : p.accentSoft,
                          ),
                        if (showNutrition && kcal > 0) TagPill(l.coreKcalApprox(kcal.round()), icon: Icons.local_fire_department_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IngredientCard extends StatelessWidget {
  const IngredientCard({
    super.key,
    required this.lot,
    required this.today,
    this.locationName,
    this.onTap,
    this.onQuickUse,
  });

  final InventoryLot lot;
  final CalendarDate today;
  final String? locationName;
  final VoidCallback? onTap;
  final VoidCallback? onQuickUse;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = lot.statusOn(today);
    final days = lot.daysLeft(today);
    final l = context.l10n;
    final qty = context.formatQty(lot.quantity);
    final freshness = days == null
        ? null
        : days < 0
            ? (lot.daysLeftIsEstimate ? l.coreLikelyPastBest : l.corePastRecordedDate)
            : days == 0
                ? l.commonToday
                : lot.daysLeftIsEstimate
                    ? l.coreDaysLeftApprox(days)
                    : l.coreDaysLeft(days);
    return Semantics(
      button: onTap != null,
      label: [lot.productName, qty, context.labelOf(status), ?freshness].join(', '),
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.l),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: p.surfaceSoft, borderRadius: BorderRadius.circular(Radii.m)),
                  child: Icon(categoryIcon(lot.category), color: context.colors.primary, size: 22),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lot.productName, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(qty, style: context.text.bodySmall?.copyWith(color: p.ink)),
                          if (freshness != null) Text('· $freshness', style: context.text.bodySmall), // l10n-ignore: separator before translated text
                          if (locationName != null) Text('· $locationName', style: context.text.bodySmall), // l10n-ignore: separator before a place name
                          if (status != InventoryStatus.confirmed) InventoryStatusBadge(status: status),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onQuickUse != null)
                  IconButton(tooltip: l.coreUseSome, onPressed: onQuickUse, icon: const Icon(Icons.remove_circle_outline)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData categoryIcon(FoodCategory c) => switch (c) {
      FoodCategory.produce => Icons.eco_outlined,
      FoodCategory.dairy => Icons.egg_outlined,
      FoodCategory.meat => Icons.set_meal_outlined,
      FoodCategory.seafood => Icons.phishing_outlined,
      FoodCategory.bakery => Icons.bakery_dining_outlined,
      FoodCategory.grains => Icons.grain,
      FoodCategory.pantry => Icons.inventory_2_outlined,
      FoodCategory.spices => Icons.spa_outlined,
      FoodCategory.condiments => Icons.water_drop_outlined,
      FoodCategory.frozen => Icons.ac_unit,
      FoodCategory.beverages => Icons.local_cafe_outlined,
      FoodCategory.snacks => Icons.cookie_outlined,
      FoodCategory.prepared => Icons.takeout_dining_outlined,
      FoodCategory.other => Icons.category_outlined,
      FoodCategory.nonFood => Icons.cleaning_services_outlined,
    };

/// Nutrition with explicit "estimate" labelling and data completeness.
class NutritionSummaryCard extends StatelessWidget {
  const NutritionSummaryCard({super.key, required this.nutrition, this.title, this.subtitle, this.showCalories = true});

  final NutrientProfile nutrition;

  /// Defaults to "Nutrition" in the current language.
  final String? title;

  /// Defaults to "per serving" in the current language.
  final String? subtitle;
  final bool showCalories;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = [
      if (showCalories) (Nutrient.energyKcal, nutrition[Nutrient.energyKcal]),
      (Nutrient.protein, nutrition[Nutrient.protein]),
      (Nutrient.carbohydrate, nutrition[Nutrient.carbohydrate]),
      (Nutrient.fat, nutrition[Nutrient.fat]),
      (Nutrient.fibre, nutrition[Nutrient.fibre]),
      (Nutrient.sodium, nutrition[Nutrient.sodium]),
    ];
    final incomplete = nutrition.completeness < 0.9;
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title ?? l.coreNutritionTitle, style: context.text.titleMedium)),
                TagPill(l.coreEstimate, icon: Icons.info_outline, background: p.infoSoft, color: p.info),
              ],
            ),
            Text(subtitle ?? l.corePerServing, style: context.text.bodySmall),
            const SizedBox(height: Space.m),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 420 ? 6 : 3;
              final w = (c.maxWidth - (cols - 1) * Space.xs) / cols;
              return Wrap(
                spacing: Space.xs,
                runSpacing: Space.m,
                children: [
                  for (final (n, v) in items)
                    SizedBox(
                      width: w,
                      child: Semantics(
                        label: l.coreNutrientAbout(context.labelOf(n), formatNutrientFor(context, n, v)),
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(formatNutrientFor(context, n, v), style: context.text.titleLarge),
                            Text(context.labelOf(n), style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
            if (incomplete) ...[
              const SizedBox(height: Space.s),
              Text(
                nutrition.completeness == 0
                    ? l.coreNutritionNoData
                    : l.coreNutritionPartial((nutrition.completeness * 100).round()),
                style: context.text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MealTimelineItem extends StatelessWidget {
  const MealTimelineItem({super.key, required this.time, required this.title, required this.mealType, this.subtitle, this.onTap, this.isLast = false, this.done = false});

  final DateTime time;
  final String title;
  final MealType mealType;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool isLast;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: onTap != null,
      label: done
          ? context.l10n.coreMealAtDone(context.labelOf(mealType), formatTime(context, time), title)
          : context.l10n.coreMealAt(context.labelOf(mealType), formatTime(context, time), title),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.m),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 64,
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Text(formatTime(context, time), style: context.text.labelMedium?.copyWith(color: p.muted)),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: Space.s + 2),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? context.colors.primary : p.surface,
                      border: Border.all(color: context.colors.primary, width: 2),
                    ),
                  ),
                  if (!isLast) Expanded(child: Container(width: 1.5, color: p.hairline)),
                ],
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.labelOf(mealType).toUpperCase(), style: context.text.labelSmall),
                      Text(title, style: context.text.titleMedium?.copyWith(decoration: done ? TextDecoration.lineThrough : null)),
                      if (subtitle != null) Text(subtitle!, style: context.text.bodySmall),
                      const SizedBox(height: Space.s),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MorningRoutineCard extends StatelessWidget {
  const MorningRoutineCard({super.key, required this.routine, this.breakfastTitle, this.onTap});

  final MorningRoutine routine;
  final String? breakfastTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    // "06:45" as stored; French shows "6 h 45".
    String clock(String hhmm) {
      if (!localeTag(context).startsWith('fr')) return hhmm;
      final parts = hhmm.split(':');
      final h = int.tryParse(parts.first), m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
      return h == null || m == null ? hhmm : formatTime(context, DateTime(2000, 1, 1, h, m));
    }
    return Card(
      color: p.surfaceSoft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.l),
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Row(
            children: [
              Icon(routine.enabled ? Icons.alarm_on : Icons.alarm_add_outlined, color: context.colors.primary, size: 28),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.enabled ? l.coreMorningRoutine : l.coreSetUpMornings, style: context.text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      routine.enabled
                          ? l.coreMorningSummary(clock(routine.wakeTime), clock(routine.departureTime), routine.availableMinutes)
                          : l.coreMorningPitch,
                      style: context.text.bodySmall,
                    ),
                    if (routine.enabled && breakfastTitle != null) ...[
                      const SizedBox(height: 4),
                      Text(l.coreBreakfastLine(breakfastTitle!), style: context.text.bodySmall?.copyWith(color: p.ink)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}
