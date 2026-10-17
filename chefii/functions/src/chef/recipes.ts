import { randomUUID } from 'node:crypto';
import { bestMatch } from '../matching';
import { checkIngredients, DietaryProfile, isBlocked } from '../safety/allergens';
import { AiRecipe, MealEstimate } from '../schemas';
import { catalogById, parseUnit, toGrams } from '../shared';

/** Recipe in the Flutter app's Firestore map shape (Recipe.fromMap). */
export interface AppRecipe {
  id: string;
  title: string;
  summary: string;
  cuisine: string;
  mealTypes: string[];
  servings: number;
  prepMinutes: number;
  cookMinutes: number;
  difficulty: string;
  ingredients: Array<Record<string, unknown>>;
  steps: Array<Record<string, unknown>>;
  origin: 'ai';
  tags: string[];
  equipment: string[];
  storageNotes?: string;
  aiModel: string;
  imageKey: string;
}

const IMAGE_KEYS = ['tomato', 'citrus', 'herb', 'berry', 'butter', 'spice', 'avocado', 'roast', 'ginger', 'earth', 'cream', 'orchard'];

/** Basic sanity beyond the schema: no empty steps, sensible amounts. */
export function plausible(r: AiRecipe): boolean {
  if (!r.title.trim() || r.steps.some((s) => !s.text.trim())) return false;
  if (r.prepMinutes + r.cookMinutes <= 0) return false;
  return r.ingredients.every((i) => i.name.trim() && (i.quantity === null || (i.quantity > 0 && i.quantity < 10_000)));
}

export function toAppRecipe(r: AiRecipe, model: string): AppRecipe {
  return {
    id: `ai_${randomUUID().slice(0, 12)}`,
    title: r.title.trim().slice(0, 80),
    summary: r.summary.trim().slice(0, 240),
    cuisine: r.cuisine.trim().slice(0, 40) || 'Modern',
    mealTypes: r.mealTypes,
    servings: r.servings,
    prepMinutes: r.prepMinutes,
    cookMinutes: r.cookMinutes,
    difficulty: r.difficulty,
    ingredients: r.ingredients.map((i) => {
      const match = bestMatch(i.name, 0.6);
      const unit = parseUnit(i.unit);
      return {
        name: i.name.trim().slice(0, 60),
        ...(match ? { productId: match.product.id, nutrientRefId: match.product.id } : {}),
        ...(i.quantity !== null && unit ? { quantity: { amount: i.quantity, unit } } : {}),
        ...(i.preparation ? { preparation: i.preparation.slice(0, 60) } : {}),
        optional: i.optional,
      };
    }),
    steps: r.steps.map((s) => ({
      text: s.text.trim(),
      ...(s.timerMinutes && s.timerMinutes > 0 && s.timerMinutes <= 480 ? { timerSeconds: Math.round(s.timerMinutes * 60), timerLabel: s.timerLabel ?? 'Timer' } : {}),
      ...(s.tip ? { tip: s.tip } : {}),
    })),
    origin: 'ai',
    tags: [],
    equipment: r.equipment.slice(0, 10),
    ...(r.storageNotes ? { storageNotes: r.storageNotes } : {}),
    aiModel: model,
    imageKey: IMAGE_KEYS[Math.abs([...r.title].reduce((a, c) => a + c.charCodeAt(0), 0)) % IMAGE_KEYS.length],
  };
}

/**
 * Recipe text other than ingredient names: a step such as "garnish with
 * peanuts" or a preparation "fried in peanut oil" must block like an
 * ingredient would.
 */
export function recipeFreeText(r: AppRecipe): string[] {
  return [
    r.title,
    r.summary,
    ...r.ingredients.map((i) => String(i.preparation ?? '')),
    ...r.steps.flatMap((s) => [String(s.text ?? ''), String(s.tip ?? '')]),
    r.storageNotes ?? '',
  ].filter((t) => t.trim());
}

/** True when free text (e.g. a chat reply) names something the household must avoid. */
export function textConflicts(text: string, dietary: DietaryProfile): boolean {
  const sentences = text.split(/(?<=[.!?\n])\s+/).filter((t) => t.trim());
  return isBlocked(checkIngredients(sentences.map((name) => ({ name })), dietary));
}

/** Converts, screens and filters generated recipes. */
export function screenRecipes(recipes: AiRecipe[], dietary: DietaryProfile, model: string): { recipes: AppRecipe[]; rationales: string[]; filtered: number } {
  const out: AppRecipe[] = [];
  const rationales: string[] = [];
  let filtered = 0;
  for (const r of recipes) {
    if (!plausible(r)) {
      filtered++;
      continue;
    }
    const app = toAppRecipe(r, model);
    const conflicts = checkIngredients(
      [
        ...app.ingredients.map((i) => ({ name: String(i.name), allergens: catalogById.get(String(i.productId ?? ''))?.allergens ?? [] })),
        ...recipeFreeText(app).map((name) => ({ name })),
      ],
      dietary,
    );
    if (isBlocked(conflicts)) {
      filtered++;
      continue;
    }
    out.push(app);
    rationales.push(r.rationale.slice(0, 200));
  }
  return { recipes: out, rationales, filtered };
}

/**
 * Nutrition for a described meal, computed from reference data — the model
 * only identifies foods and portions, never the nutrient numbers.
 */
export function nutritionForEstimate(e: MealEstimate): { values: Record<string, number>; completeness: number; isEstimate: true } {
  const values: Record<string, number> = {};
  let counted = 0;
  for (const item of e.items) {
    // A wrong match is worse than none: weak matches count as unknown.
    const m = bestMatch(item.name, 0.65);
    const grams = item.grams ?? (m?.product.gramsPerPiece ?? null);
    if (!m || grams === null || grams <= 0 || grams > 3000) continue;
    counted++;
    for (const [k, v] of Object.entries(m.product.per100g)) values[k] = (values[k] ?? 0) + (v * grams) / 100;
  }
  for (const k of Object.keys(values)) values[k] = Math.round(values[k] * 100) / 100;
  return { values, completeness: e.items.length ? counted / e.items.length : 0, isEstimate: true };
}

export { toGrams };
