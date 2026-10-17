import Ajv, { ErrorObject, ValidateFunction } from 'ajv';
import { FOOD_CATEGORIES, MEAL_TYPES, STORAGE, UNITS } from './shared';

/**
 * AI output contracts.
 *
 * Each schema is written in the subset both providers accept for structured
 * output (Gemini `responseJsonSchema`, OpenAI strict `json_schema`): every
 * property required, nullability via type unions, no `pattern`/`format`.
 * After generation, output is re-validated here with Ajv *plus* tighter
 * semantic bounds, and anything that fails is rejected — never "repaired".
 * Mirrored in docs/AI_CONTRACTS.md.
 */
type Json = Record<string, unknown>;

const str = { type: 'string' } as const;
const nullableStr = { type: ['string', 'null'] } as const;
const nullableNum = { type: ['number', 'null'] } as const;
const nullableInt = { type: ['integer', 'null'] } as const;
const obj = (properties: Record<string, unknown>): Json => ({
  type: 'object',
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});

export const receiptExtractionSchema = obj({
  isReceipt: { type: 'boolean', description: 'False if the image is not a purchase receipt.' },
  imageQuality: { type: 'string', enum: ['good', 'blurry', 'dark', 'cut_off', 'partial'] },
  merchant: nullableStr,
  purchaseDate: { type: ['string', 'null'], description: 'YYYY-MM-DD exactly as printed, else null.' },
  currency: { type: ['string', 'null'], description: 'ISO 4217, e.g. CAD.' },
  subtotalCents: nullableInt,
  taxCents: nullableInt,
  totalCents: nullableInt,
  lines: {
    type: 'array',
    maxItems: 150,
    items: obj({
      rawText: { type: 'string', description: 'The line exactly as printed.' },
      name: { type: 'string', description: 'Plain product name, or empty string if unknown.' },
      brand: nullableStr,
      category: { type: 'string', enum: [...FOOD_CATEGORIES] },
      isFood: { type: 'boolean' },
      quantity: { type: ['number', 'null'], description: 'Only if printed or unambiguous from the package size; else null.' },
      unit: { type: ['string', 'null'], enum: [...UNITS, null] },
      packageDescription: nullableStr,
      unitPriceCents: nullableInt,
      totalPriceCents: nullableInt,
      storage: { type: 'string', enum: [...STORAGE] },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
    }),
  },
});

const ingredient = obj({
  name: str,
  quantity: nullableNum,
  unit: { type: ['string', 'null'], enum: [...UNITS, null] },
  preparation: nullableStr,
  optional: { type: 'boolean' },
});

const step = obj({
  text: str,
  timerMinutes: nullableNum,
  timerLabel: nullableStr,
  tip: nullableStr,
});

export const recipeSchema = obj({
  title: str,
  summary: str,
  cuisine: str,
  mealTypes: { type: 'array', items: { type: 'string', enum: [...MEAL_TYPES] }, minItems: 1, maxItems: 4 },
  servings: { type: 'integer', minimum: 1, maximum: 16 },
  prepMinutes: { type: 'integer', minimum: 0, maximum: 240 },
  cookMinutes: { type: 'integer', minimum: 0, maximum: 480 },
  difficulty: { type: 'string', enum: ['easy', 'medium', 'involved'] },
  equipment: { type: 'array', items: str, maxItems: 10 },
  ingredients: { type: 'array', items: ingredient, minItems: 1, maxItems: 30 },
  steps: { type: 'array', items: step, minItems: 1, maxItems: 20 },
  rationale: { type: 'string', description: 'One sentence on why this suits the request.' },
  storageNotes: nullableStr,
});

export const recipeListSchema = obj({
  recipes: { type: 'array', items: recipeSchema, minItems: 0, maxItems: 5 },
});

export const chatReplySchema = obj({
  text: { type: 'string', description: 'Warm, concise reply. No medical claims.' },
  recipes: { type: 'array', items: recipeSchema, maxItems: 3 },
});

export const scanSchema = obj({
  isFoodStorage: { type: 'boolean' },
  items: {
    type: 'array',
    maxItems: 40,
    items: obj({
      name: str,
      category: { type: 'string', enum: [...FOOD_CATEGORIES] },
      visibleCount: { type: ['integer', 'null'], description: 'Only if individual items are clearly countable; else null.' },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
      note: nullableStr,
    }),
  },
  message: nullableStr,
});

export const mealEstimateSchema = obj({
  title: str,
  items: {
    type: 'array',
    maxItems: 15,
    items: obj({ name: str, grams: { type: ['number', 'null'], description: 'Estimated grams eaten, null if unknowable.' } }),
  },
  note: nullableStr,
});

const ajv = new Ajv({ allErrors: true, strict: false });
const cache = new Map<Json, ValidateFunction>();

export class SchemaViolation extends Error {
  constructor(public readonly errors: ErrorObject[]) {
    super(`AI output failed schema validation: ${ajv.errorsText(errors, { separator: '; ' })}`);
  }
}

/** Validates against [schema] or throws [SchemaViolation]. */
export function validate<T>(schema: Json, value: unknown): T {
  let fn = cache.get(schema);
  if (!fn) {
    fn = ajv.compile(schema);
    cache.set(schema, fn);
  }
  if (!fn(value)) throw new SchemaViolation(fn.errors ?? []);
  return value as T;
}

// ---- typed views

export interface ReceiptExtraction {
  isReceipt: boolean;
  imageQuality: 'good' | 'blurry' | 'dark' | 'cut_off' | 'partial';
  merchant: string | null;
  purchaseDate: string | null;
  currency: string | null;
  subtotalCents: number | null;
  taxCents: number | null;
  totalCents: number | null;
  lines: Array<{
    rawText: string;
    name: string;
    brand: string | null;
    category: string;
    isFood: boolean;
    quantity: number | null;
    unit: string | null;
    packageDescription: string | null;
    unitPriceCents: number | null;
    totalPriceCents: number | null;
    storage: string;
    confidence: number;
  }>;
}

export interface AiRecipe {
  title: string;
  summary: string;
  cuisine: string;
  mealTypes: string[];
  servings: number;
  prepMinutes: number;
  cookMinutes: number;
  difficulty: string;
  equipment: string[];
  ingredients: Array<{ name: string; quantity: number | null; unit: string | null; preparation: string | null; optional: boolean }>;
  steps: Array<{ text: string; timerMinutes: number | null; timerLabel: string | null; tip: string | null }>;
  rationale: string;
  storageNotes: string | null;
}

export interface ScanResult {
  isFoodStorage: boolean;
  items: Array<{ name: string; category: string; visibleCount: number | null; confidence: number; note: string | null }>;
  message: string | null;
}

export interface MealEstimate {
  title: string;
  items: Array<{ name: string; grams: number | null }>;
  note: string | null;
}
