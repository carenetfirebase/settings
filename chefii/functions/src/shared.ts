import catalogData from './data/catalog.json';
import allergenData from './data/allergens.json';

/** Generated from the Flutter app (tool/export_shared_data.dart). */
export interface CatalogProduct {
  id: string;
  name: string;
  category: string;
  defaultUnit: string;
  defaultStorage: string;
  aliases: string[];
  allergens: string[];
  gramsPerPiece: number | null;
  gramsPerMl: number | null;
  per100g: Record<string, number>;
}

export const catalog: CatalogProduct[] = catalogData as CatalogProduct[];
export const catalogById: Map<string, CatalogProduct> = new Map(catalog.map((p) => [p.id, p]));

export const FOOD_CATEGORIES = [
  'produce', 'dairy', 'meat', 'seafood', 'bakery', 'grains', 'pantry', 'spices', 'condiments',
  'frozen', 'beverages', 'snacks', 'prepared', 'other', 'nonFood',
] as const;
export const UNITS = ['mg', 'g', 'kg', 'oz', 'lb', 'ml', 'l', 'tsp', 'tbsp', 'cup', 'piece', 'dozen'] as const;
export const STORAGE = ['fridge', 'freezer', 'pantry', 'custom'] as const;
export const MEAL_TYPES = ['breakfast', 'lunch', 'dinner', 'snack'] as const;

export interface AllergenInfo { key: string; label: string; terms: string[]; exclusions: string[] }
export interface RestrictionInfo { key: string; label: string; excludedAllergens: string[]; excludedTerms: string[]; exclusions: string[] }

export const allergenLexicon = allergenData as {
  allergens: AllergenInfo[];
  intolerances: Record<string, string>;
  restrictions: RestrictionInfo[];
};

/** Grams per unit within a dimension, mirroring lib/domain/units/units.dart. */
export const UNIT_TO_BASE: Record<string, { dim: 'mass' | 'volume' | 'count'; base: number }> = {
  mg: { dim: 'mass', base: 0.001 },
  g: { dim: 'mass', base: 1 },
  kg: { dim: 'mass', base: 1000 },
  oz: { dim: 'mass', base: 28.349523125 },
  lb: { dim: 'mass', base: 453.59237 },
  ml: { dim: 'volume', base: 1 },
  l: { dim: 'volume', base: 1000 },
  tsp: { dim: 'volume', base: 5 },
  tbsp: { dim: 'volume', base: 15 },
  cup: { dim: 'volume', base: 250 },
  piece: { dim: 'count', base: 1 },
  dozen: { dim: 'count', base: 12 },
};

const UNIT_ALIASES: Record<string, string> = {
  gram: 'g', grams: 'g', gr: 'g', kilogram: 'kg', kgs: 'kg', ounce: 'oz', ounces: 'oz', pound: 'lb', pounds: 'lb', lbs: 'lb',
  millilitre: 'ml', milliliter: 'ml', millilitres: 'ml', milliliters: 'ml', litre: 'l', liter: 'l', litres: 'l', liters: 'l',
  teaspoon: 'tsp', tablespoon: 'tbsp', cups: 'cup', pc: 'piece', pcs: 'piece', pieces: 'piece', each: 'piece', ea: 'piece', unit: 'piece', ct: 'piece',
};

export function parseUnit(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = raw.trim().toLowerCase();
  if (s in UNIT_TO_BASE) return s;
  return UNIT_ALIASES[s] ?? null;
}

/** Grams for an amount of a product, or null when it can't be known. */
export function toGrams(amount: number, unit: string, product?: CatalogProduct): number | null {
  const u = UNIT_TO_BASE[unit];
  if (!u) return null;
  const base = amount * u.base;
  if (u.dim === 'mass') return base;
  if (u.dim === 'volume') return product?.gramsPerMl ? base * product.gramsPerMl : null;
  return product?.gramsPerPiece ? base * product.gramsPerPiece : null;
}
