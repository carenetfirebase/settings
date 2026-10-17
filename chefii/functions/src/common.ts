import { initializeApp, getApps } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { AiRouter, UsageEvent } from './ai/router';
import { GeminiProvider } from './ai/gemini';
import { OpenAiProvider } from './ai/openai';
import { AiProvider, AiTask } from './ai/provider';
import { DAILY_LIMITS, GEMINI_API_KEY, GEMINI_MODEL, GEMINI_VISION_MODEL, OPENAI_API_KEY, OPENAI_ENABLED, OPENAI_MODEL } from './config';
import { DietaryProfile, mergeProfiles } from './safety/allergens';

if (!getApps().length) initializeApp();
export const db = getFirestore();
// Optional fields are left undefined in validated AI output; store them as absent.
db.settings({ ignoreUndefinedProperties: true });
export { FieldValue, Timestamp };

export function requireAuth(req: CallableRequest<unknown>): string {
  if (!req.auth?.uid) throw new HttpsError('unauthenticated', 'Please sign in.');
  return req.auth.uid;
}

export async function requireMember(householdId: unknown, uid: string): Promise<string> {
  if (typeof householdId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(householdId)) {
    throw new HttpsError('invalid-argument', 'Invalid household.');
  }
  const h = await db.doc(`households/${householdId}`).get();
  const members: string[] = h.get('memberUids') ?? [];
  if (!h.exists || !members.includes(uid)) throw new HttpsError('permission-denied', 'Not a member of this household.');
  return householdId;
}

export async function userSettings(uid: string): Promise<{ aiProcessingConsent: boolean; allowOptionalAiProvider: boolean }> {
  const s = (await db.doc(`users/${uid}/private/settings`).get()).data() ?? {};
  return { aiProcessingConsent: s.aiProcessingConsent === true, allowOptionalAiProvider: s.allowOptionalAiProvider === true };
}

/** AI processing of personal content requires explicit consent. */
export async function requireAiConsent(uid: string) {
  const s = await userSettings(uid);
  if (!s.aiProcessingConsent) {
    throw new HttpsError('failed-precondition', 'Turn on AI processing in Privacy & data to use this feature.', { reason: 'ai_consent_required' });
  }
  return s;
}

/** Per-user daily quota, enforced transactionally. */
export async function enforceRateLimit(uid: string, task: AiTask): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const ref = db.doc(`rateLimits/${uid}_${day}`);
  const limit = DAILY_LIMITS[task] ?? 50;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = (snap.get(task) as number | undefined) ?? 0;
    if (used >= limit) throw new HttpsError('resource-exhausted', 'You\'ve reached today\'s limit for this feature. Please try again tomorrow.');
    tx.set(ref, { [task]: used + 1, uid, day, expiresAt: Timestamp.fromMillis(Date.now() + 3 * 86400_000) }, { merge: true });
  });
}

/** Records cost/latency metadata only — never prompts, images or outputs. */
function usageLogger(uid: string) {
  return async (e: UsageEvent) => {
    try {
      await db.collection('aiUsage').add({ uid, ...e, at: FieldValue.serverTimestamp() });
    } catch (err) {
      logger.warn('aiUsage write failed', { task: e.task });
    }
  };
}

/**
 * Integration tests (src/*.int.test.ts) swap in a deterministic provider.
 * Only honoured under the emulator suite, never in a deployed function.
 */
export const testHooks: { provider?: AiProvider } = {};
const testHooksAllowed = () => process.env.CHEFII_INTEGRATION_TEST === '1' && !!process.env.FIRESTORE_EMULATOR_HOST;

export function makeRouter(uid: string, allowOptional: boolean): AiRouter {
  if (testHooks.provider && testHooksAllowed()) {
    return new AiRouter({ primary: testHooks.provider, allowOptional: false, onUsage: usageLogger(uid) });
  }
  const primary = new GeminiProvider(GEMINI_API_KEY.value(), GEMINI_MODEL.value(), GEMINI_VISION_MODEL.value());
  const optional = OPENAI_ENABLED.value() && OPENAI_API_KEY.value() ? new OpenAiProvider(OPENAI_API_KEY.value(), OPENAI_MODEL.value()) : undefined;
  return new AiRouter({ primary, optional, allowOptional, onUsage: usageLogger(uid) });
}

/** The requesting user's profile merged with allergens other members shared. */
export async function householdDietary(uid: string, householdId: string): Promise<DietaryProfile> {
  const mine = (await db.doc(`users/${uid}/private/dietary`).get()).data() ?? {};
  const members = await db.collection(`households/${householdId}/members`).get();
  const shared = members.docs.filter((d) => d.id !== uid).flatMap((d) => (d.get('sharedAllergens') as string[] | undefined) ?? []);
  const base: DietaryProfile = {
    allergyStatus: mine.allergyStatus,
    allergies: mine.allergies ?? [],
    intolerances: mine.intolerances ?? [],
    restrictions: mine.restrictions ?? [],
    dislikes: mine.dislikes ?? [],
  };
  return mergeProfiles(base, { allergies: shared, intolerances: [], restrictions: [], dislikes: [] });
}

export function fmtQty(q: { amount?: number; unit?: string } | undefined): string {
  return q?.amount === undefined ? '' : `${Math.round(q.amount * 100) / 100} ${q.unit ?? ''}`.trim();
}

export function mapProviderError(e: unknown): never {
  if (e instanceof HttpsError) throw e;
  const retryable = (e as { retryable?: boolean }).retryable;
  logger.error('AI failure', { error: (e as Error).message });
  throw new HttpsError(retryable === false ? 'failed-precondition' : 'unavailable', 'The kitchen assistant is unavailable right now. Please try again shortly.');
}
