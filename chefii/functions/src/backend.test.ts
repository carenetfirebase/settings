import { describe, expect, it } from 'vitest';
import { FakeProvider } from './ai/fake';
import { ProviderError } from './ai/provider';
import { AiRouter, UsageEvent } from './ai/router';
import { nutritionForEstimate, screenRecipes } from './chef/recipes';
import { bestMatch } from './matching';
import { validateExtraction, validDate } from './receipts/validate';
import { checkIngredients, detectAllergens, isBlocked } from './safety/allergens';
import { AiRecipe, ReceiptExtraction, receiptExtractionSchema, recipeListSchema, SchemaViolation, validate } from './schemas';

const line = (over: Partial<ReceiptExtraction['lines'][number]> = {}): ReceiptExtraction['lines'][number] => ({
  rawText: 'LG EGGS 12CT', name: 'Eggs', brand: null, category: 'dairy', isFood: true, quantity: 12, unit: 'piece',
  packageDescription: null, unitPriceCents: null, totalPriceCents: 479, storage: 'fridge', confidence: 0.95, ...over,
});

const receipt = (over: Partial<ReceiptExtraction> = {}): ReceiptExtraction => ({
  isReceipt: true, imageQuality: 'good', merchant: 'Maison Market', purchaseDate: '2026-10-10', currency: 'CAD',
  subtotalCents: 479, taxCents: 0, totalCents: 479, lines: [line()], ...over,
});

const now = new Date('2026-10-15T12:00:00Z');

describe('receipt validation', () => {
  it('normalises a clean receipt and matches the catalogue', () => {
    const v = validateExtraction(receipt(), now);
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    expect(v.lines[0]).toMatchObject({ id: 'l1', name: 'Eggs', matchedProductId: 'egg', quantity: { amount: 12, unit: 'piece' }, excluded: false });
    expect(v.issues).toEqual([]);
    expect(v.fingerprint).toMatch(/^[0-9a-f]{40}$/);
  });

  it('rejects non-receipts and empty extractions', () => {
    expect(validateExtraction(receipt({ isReceipt: false, lines: [] }), now)).toMatchObject({ ok: false, errorCode: 'not_a_receipt' });
    expect(validateExtraction(receipt({ lines: [], imageQuality: 'blurry' }), now)).toMatchObject({ ok: false, errorCode: 'unreadable' });
  });

  it('never invents quantities: missing amounts are flagged and lower confidence', () => {
    const v = validateExtraction(receipt({ lines: [line({ quantity: null, unit: null, confidence: 0.9 })] }), now);
    if (!v.ok) throw new Error('expected ok');
    expect(v.lines[0].quantity).toBeUndefined();
    expect(v.lines[0].confidence).toBeLessThanOrEqual(0.6);
    expect(v.lines[0].issues.join()).toContain('Quantity');
  });

  it('flags totals that do not reconcile and lowers confidence', () => {
    const v = validateExtraction(receipt({ subtotalCents: 999 }), now);
    if (!v.ok) throw new Error('expected ok');
    expect(v.issues.map((i) => i.code)).toContain('totals_mismatch');
    expect(v.lines[0].confidence).toBeLessThanOrEqual(0.85);
  });

  it('excludes non-food and discount lines, flags duplicates', () => {
    const v = validateExtraction(receipt({
      subtotalCents: null,
      lines: [
        line(),
        line(),
        line({ rawText: 'DISH SOAP', name: 'Dish soap', category: 'nonFood', isFood: false, totalPriceCents: 349, quantity: null, unit: null }),
        line({ rawText: 'COUPON', name: 'Coupon', category: 'other', isFood: true, totalPriceCents: -100, quantity: null, unit: null }),
      ],
    }), now);
    if (!v.ok) throw new Error('expected ok');
    expect(v.lines[1].issues.join()).toContain('duplicate');
    expect(v.lines[2]).toMatchObject({ isFood: false, excluded: true, category: 'nonFood' });
    expect(v.lines[3]).toMatchObject({ isFood: false, excluded: true });
  });

  it('drops implausible dates and bad units', () => {
    expect(validDate('2031-01-01', now)).toBeNull();
    expect(validDate('2026-02-30', now)).toBeNull();
    expect(validDate('2026-10-14', now)).toBe('2026-10-14');
    const v = validateExtraction(receipt({ lines: [line({ unit: 'furlong' })] }), now);
    if (!v.ok) throw new Error('expected ok');
    expect(v.lines[0].quantity).toBeUndefined();
  });
});

describe('allergen guard parity with the Flutter app', () => {
  it('matches the Dart test expectations', () => {
    expect(detectAllergens('unsalted butter').has('milk')).toBe(true);
    expect(detectAllergens('coconut milk').has('milk')).toBe(false);
    expect(detectAllergens('peanut butter').has('peanut')).toBe(true);
    expect(detectAllergens('peanut butter').has('milk')).toBe(false);
    expect(detectAllergens('eggplant').has('egg')).toBe(false);
    expect([...detectAllergens('soy sauce')]).toEqual(expect.arrayContaining(['soy', 'wheat', 'gluten']));
    expect(detectAllergens('tamari').has('wheat')).toBe(false);
    expect(detectAllergens('toasted almonds').has('tree_nut')).toBe(true);
    expect(detectAllergens('Swiss chard').has('fish')).toBe(false);
  });

  it('blocks allergy and restriction conflicts', () => {
    const c = checkIngredients([{ name: 'parmesan' }, { name: 'basil' }], { allergies: ['milk'], intolerances: [], restrictions: [], dislikes: ['basil'] });
    expect(isBlocked(c)).toBe(true);
    expect(c.map((x) => x.severity)).toEqual(['allergy', 'dislike']);
    expect(isBlocked(checkIngredients([{ name: 'chicken breast' }], { allergies: [], intolerances: [], restrictions: ['vegetarian'], dislikes: [] }))).toBe(true);
  });
});

describe('product matching', () => {
  it('matches receipt abbreviations like the app does', () => {
    expect(bestMatch('BNLS SKNLS CHKN BRST')?.product.id).toBe('chicken_breast');
    expect(bestMatch('MLK 2%')?.product.id).toBe('milk');
    // Québec receipts are often printed in French, in capitals, without accents.
    expect(bestMatch('OEUFS GROS CAL 12')?.product.id).toBe('egg');
    expect(bestMatch('LAIT 2% 4L')?.product.id).toBe('milk');
    expect(bestMatch('BOEUF HACHE MAIGRE')?.product.id).toBe('ground_beef');
    expect(bestMatch('POMMES DE TERRE')?.product.id).toBe('potato');
    expect(bestMatch('dish soap')).toBeNull();
  });
});

const recipe = (over: Partial<AiRecipe> = {}): AiRecipe => ({
  title: 'Peanut noodles', summary: 'Quick and nutty.', cuisine: 'Thai-inspired', mealTypes: ['dinner'], servings: 2,
  prepMinutes: 10, cookMinutes: 10, difficulty: 'easy', equipment: ['Pot'],
  ingredients: [
    { name: 'rice noodles', quantity: 200, unit: 'g', preparation: null, optional: false },
    { name: 'peanut butter', quantity: 40, unit: 'g', preparation: null, optional: false },
  ],
  steps: [{ text: 'Cook the noodles.', timerMinutes: 8, timerLabel: 'Noodles', tip: null }],
  rationale: 'Uses your peanut butter.', storageNotes: null, ...over,
});

describe('AI recipes are screened deterministically', () => {
  it('removes recipes that conflict with allergies, keeps safe ones', () => {
    const safe = recipe({ title: 'Garlic rice', ingredients: [{ name: 'basmati rice', quantity: 150, unit: 'g', preparation: null, optional: false }] });
    const r = screenRecipes([recipe(), safe], { allergies: ['peanut'], intolerances: [], restrictions: [], dislikes: [] }, 'fake:1');
    expect(r.filtered).toBe(1);
    expect(r.recipes.map((x) => x.title)).toEqual(['Garlic rice']);
    expect(r.recipes[0].ingredients[0]).toMatchObject({ productId: 'rice', quantity: { amount: 150, unit: 'g' } });
    expect(r.recipes[0].origin).toBe('ai');
  });

  it('rejects implausible recipes', () => {
    const r = screenRecipes([recipe({ steps: [{ text: ' ', timerMinutes: null, timerLabel: null, tip: null }] })], { allergies: [], intolerances: [], restrictions: [], dislikes: [] }, 'x');
    expect(r.recipes).toHaveLength(0);
  });

  it('computes meal nutrition from reference data, not the model', () => {
    const n = nutritionForEstimate({ title: 'Eggs', items: [{ name: 'eggs', grams: 100 }, { name: 'mystery sauce', grams: 20 }], note: null });
    expect(n.values.energyKcal).toBeCloseTo(143, 0);
    expect(n.completeness).toBe(0.5);
  });
});

describe('schemas', () => {
  it('accept valid output and reject malformed output', () => {
    expect(() => validate(receiptExtractionSchema, receipt())).not.toThrow();
    expect(() => validate(receiptExtractionSchema, { ...receipt(), lines: [{ ...line(), confidence: 2 }] })).toThrow(SchemaViolation);
    expect(() => validate(receiptExtractionSchema, { ...receipt(), extra: true })).toThrow(SchemaViolation);
    expect(() => validate(recipeListSchema, { recipes: [{ ...recipe(), servings: 0 }] })).toThrow(SchemaViolation);
  });
});

describe('AI router', () => {
  const req = { task: 'chat' as const, system: 's', messages: [{ role: 'user' as const, text: 'hi' }], schema: recipeListSchema, schemaName: 'r' };

  it('uses the optional provider only when enabled and allowed, falling back on failure', async () => {
    const primary = new FakeProvider(() => ({ recipes: [] }));
    const optional = new FakeProvider(() => new ProviderError('down', true, 'openai'));
    const usage: UsageEvent[] = [];
    const router = new AiRouter({ primary, optional, allowOptional: true, onUsage: (e) => void usage.push(e) });
    const out = await router.run(req);
    expect(out.data).toEqual({ recipes: [] });
    expect(optional.calls).toHaveLength(1);
    expect(primary.calls).toHaveLength(1);
    expect(usage.map((u) => u.ok)).toEqual([false, true]);

    const respectful = new AiRouter({ primary, optional, allowOptional: false });
    await respectful.run(req);
    expect(optional.calls).toHaveLength(1); // not called again
  });

  it('routes images to the primary provider only', () => {
    const p = new FakeProvider(() => ({}));
    const o = new FakeProvider(() => ({}));
    expect(new AiRouter({ primary: p, optional: o, allowOptional: true }).chain('receipt', true)).toEqual([p]);
  });

  it('rejects schema-invalid output instead of returning it', async () => {
    const bad = new FakeProvider(() => ({ recipes: 'nope' }));
    await expect(new AiRouter({ primary: bad, allowOptional: false }).run(req)).rejects.toBeInstanceOf(ProviderError);
  });

  it('does not retry non-retryable failures', async () => {
    const p = new FakeProvider(() => new ProviderError('bad request', false, 'openai'));
    const g = new FakeProvider(() => ({ recipes: [] }));
    await expect(new AiRouter({ primary: g, optional: p, allowOptional: true }).run(req)).rejects.toThrow('bad request');
    expect(g.calls).toHaveLength(0);
  });
});
