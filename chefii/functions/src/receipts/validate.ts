import { createHash } from 'node:crypto';
import { bestMatch } from '../matching';
import { ReceiptExtraction } from '../schemas';
import { parseUnit } from '../shared';

export interface ReceiptIssue { code: string; message: string; lineId?: string }

export interface NormalisedLine {
  id: string;
  rawText: string;
  name: string;
  brand?: string;
  category: string;
  confidence: number;
  quantity?: { amount: number; unit: string };
  packageDescription?: string;
  unitPrice?: { minor: number; currency: string };
  totalPrice?: { minor: number; currency: string };
  matchedProductId?: string;
  isFood: boolean;
  excluded: boolean;
  storage: string;
  userEdited: false;
  issues: string[];
}

export type ValidationOutcome =
  | { ok: false; errorCode: 'not_a_receipt' | 'unreadable'; message: string }
  | {
      ok: true;
      merchant: string | null;
      purchaseDate: string | null;
      currency: string;
      subtotal: number | null;
      tax: number | null;
      total: number | null;
      lines: NormalisedLine[];
      issues: ReceiptIssue[];
      fingerprint: string | null;
    };

const DEFAULT_STORAGE: Record<string, string> = {
  produce: 'fridge', dairy: 'fridge', meat: 'fridge', seafood: 'fridge', frozen: 'freezer', prepared: 'fridge',
};

const clampStr = (s: string | null | undefined, max: number): string | undefined => {
  const t = (s ?? '').replace(/\s+/g, ' ').trim();
  return t ? t.slice(0, max) : undefined;
};

/** Plausible calendar date not in the future (2-day grace for time zones). */
export function validDate(s: string | null, now = new Date()): string | null {
  if (!s || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T12:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) return null;
  if (d.getTime() > now.getTime() + 2 * 86400_000) return null;
  if (d.getTime() < now.getTime() - 3 * 365 * 86400_000) return null;
  return s;
}

/**
 * Deterministic checks applied to model output. The model's numbers are
 * never trusted blindly: totals are reconciled, units parsed, implausible
 * values dropped (to be asked of the user), and confidence lowered where
 * the receipt and our checks disagree.
 */
export function validateExtraction(x: ReceiptExtraction, now = new Date()): ValidationOutcome {
  if (!x.isReceipt) return { ok: false, errorCode: 'not_a_receipt', message: 'That doesn\'t look like a receipt.' };
  if (x.lines.length === 0) {
    return { ok: false, errorCode: 'unreadable', message: x.imageQuality === 'good' ? 'We couldn\'t find any items.' : 'The photo is too hard to read.' };
  }
  const currency = /^[A-Z]{3}$/.test(x.currency ?? '') ? x.currency! : 'CAD';
  const money = (c: number | null) => (c === null || !Number.isInteger(c) || Math.abs(c) > 10_000_000 ? undefined : { minor: c, currency });
  const issues: ReceiptIssue[] = [];
  const lines: NormalisedLine[] = [];
  const seen = new Map<string, number>();

  x.lines.slice(0, 150).forEach((l, i) => {
    const id = `l${i + 1}`;
    const lineIssues: string[] = [];
    let confidence = Math.min(Math.max(l.confidence, 0), 1);
    const name = clampStr(l.name, 80) ?? '';
    const price = money(l.totalPriceCents);
    const isDiscount = (price?.minor ?? 0) < 0;
    let isFood = l.isFood && l.category !== 'nonFood' && !isDiscount;

    let quantity: NormalisedLine['quantity'];
    const unit = parseUnit(l.unit);
    if (l.quantity !== null && unit && l.quantity > 0 && l.quantity < 100_000) {
      quantity = { amount: Math.round(l.quantity * 1000) / 1000, unit };
    } else if (isFood) {
      lineIssues.push('Quantity not printed — please enter how much');
      confidence = Math.min(confidence, 0.6);
    }
    if (!name && isFood) {
      lineIssues.push('Could not identify this item');
      confidence = Math.min(confidence, 0.3);
    }
    if (isDiscount) lineIssues.push('Discount or coupon line');

    const key = `${l.rawText.trim().toLowerCase()}|${price?.minor ?? ''}`;
    if (seen.has(key)) {
      lineIssues.push('Possible duplicate of an earlier line');
      issues.push({ code: 'possible_duplicate_line', message: `"${l.rawText}" appears more than once`, lineId: id });
    }
    seen.set(key, i);

    const match = name ? bestMatch(name, 0.75) : null;
    if (!isFood && l.category === 'nonFood') isFood = false;
    lines.push({
      id,
      rawText: clampStr(l.rawText, 120) ?? '',
      name,
      brand: clampStr(l.brand, 60),
      category: isFood ? l.category : 'nonFood',
      confidence: Math.round(confidence * 100) / 100,
      quantity,
      packageDescription: clampStr(l.packageDescription, 60),
      unitPrice: money(l.unitPriceCents),
      totalPrice: price,
      matchedProductId: match?.product.id,
      isFood,
      excluded: !isFood,
      storage: l.storage === 'custom' || !isFood ? (DEFAULT_STORAGE[l.category] ?? 'pantry') : l.storage,
      userEdited: false,
      issues: lineIssues,
    });
  });

  const subtotal = x.subtotalCents ?? (x.totalCents !== null && x.taxCents !== null ? x.totalCents - x.taxCents : null);
  const linesSum = lines.reduce((s, l) => s + (l.totalPrice?.minor ?? 0), 0);
  const unpriced = lines.filter((l) => !l.totalPrice).length;
  if (subtotal !== null && unpriced === 0 && Math.abs(linesSum - subtotal) > 2) {
    issues.push({
      code: 'totals_mismatch',
      message: `Items add up to ${(linesSum / 100).toFixed(2)} but the subtotal reads ${(subtotal / 100).toFixed(2)}. A line may be missing or misread.`,
    });
    // Everything is a little less certain when totals disagree.
    for (const l of lines) l.confidence = Math.round(Math.min(l.confidence, 0.85) * 100) / 100;
  }
  if (x.imageQuality !== 'good') issues.push({ code: `quality_${x.imageQuality}`, message: 'Part of the receipt was hard to read — please check the items.' });

  const merchant = clampStr(x.merchant, 60) ?? null;
  const purchaseDate = validDate(x.purchaseDate, now);
  const fingerprint = merchant && purchaseDate && x.totalCents !== null
    ? createHash('sha256').update(`${merchant.toLowerCase().replace(/[^a-z0-9]/g, '')}|${purchaseDate}|${x.totalCents}|${lines.length}`).digest('hex').slice(0, 40)
    : null;

  return {
    ok: true,
    merchant,
    purchaseDate,
    currency,
    subtotal: x.subtotalCents,
    tax: x.taxCents,
    total: x.totalCents,
    lines,
    issues,
    fingerprint,
  };
}
