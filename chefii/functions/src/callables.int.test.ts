import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import type { CallableRequest } from 'firebase-functions/v2/https';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { FakeProvider } from './ai/fake';
import { StructuredRequest } from './ai/provider';
import { db, testHooks, Timestamp } from './common';
import { acceptHouseholdInvite, chefRecommend, deleteAccountData, onMemberRemoved, processReceipt } from './index';
import { AiRecipe, ReceiptExtraction } from './schemas';

/**
 * Callable integration tests against the Firestore, Auth and Storage
 * emulators. Handlers run through `.run()`, which skips the App Check gate
 * (covered by enforceAppCheck in the deployed config, not here).
 */
const project = 'demo-chefii';
const now = () => Math.floor(Date.now() / 1000);

type Callable = { run: (req: CallableRequest<unknown>) => unknown };
const call = (fn: unknown, uid: string | null, data: unknown, token: Record<string, unknown> = {}) =>
  Promise.resolve((fn as Callable).run({
    data,
    auth: uid ? { uid, token: { auth_time: now(), ...token } as never, rawToken: 'test' } : undefined,
    rawRequest: {} as never,
    acceptsStreaming: false,
  } as CallableRequest<unknown>));

async function clearAll() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, { method: 'DELETE' });
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  await fetch(`http://${authHost}/emulator/v1/projects/${project}/accounts`, { method: 'DELETE' });
  await getStorage().bucket().deleteFiles({ force: true }).catch(() => undefined);
}

async function seedHousehold() {
  for (const uid of ['alice', 'bob', 'carol']) await getAuth().createUser({ uid, displayName: uid[0].toUpperCase() + uid.slice(1) });
  await db.doc('households/h1').set({ name: 'Home', ownerUid: 'alice', memberUids: ['alice', 'bob'] });
  await db.doc('households/h1/members/alice').set({ displayName: 'Alice', role: 'owner', sharedAllergens: [] });
  await db.doc('households/h1/members/bob').set({ displayName: 'Bob', role: 'adult', sharedAllergens: ['peanut'] });
  await db.doc('users/alice').set({ displayName: 'Alice', householdId: 'h1' });
  await db.doc('users/bob').set({ displayName: 'Bob', householdId: 'h1' });
  await db.doc('users/carol').set({ displayName: 'Carol' });
  for (const uid of ['alice', 'bob', 'carol']) await db.doc(`users/${uid}/private/settings`).set({ aiProcessingConsent: uid !== 'carol' });
}

beforeEach(async () => {
  await clearAll();
  await seedHousehold();
});
afterEach(() => {
  testHooks.provider = undefined;
});

const expectCode = async (p: Promise<unknown>, code: string) => {
  await expect(p).rejects.toMatchObject({ code });
};

// ---------------------------------------------------------------- invites

describe('acceptHouseholdInvite', () => {
  const invite = (over: Record<string, unknown> = {}) =>
    db.doc('households/h1/invites/i1').set({ code: 'JOINME42', role: 'adult', used: false, expiresAt: Timestamp.fromMillis(Date.now() + 86400_000), ...over });

  it('joins the household once and marks the invite used', async () => {
    await invite();
    await expect(call(acceptHouseholdInvite, 'carol', { code: ' joinme42 ' })).resolves.toEqual({ householdId: 'h1' });
    expect((await db.doc('households/h1').get()).get('memberUids')).toContain('carol');
    expect((await db.doc('users/carol').get()).get('householdId')).toBe('h1');
    expect((await db.doc('households/h1/members/carol').get()).get('role')).toBe('adult');
    expect((await db.doc('households/h1/invites/i1').get()).get('used')).toBe(true);
    await getAuth().createUser({ uid: 'dave' });
    await expectCode(call(acceptHouseholdInvite, 'dave', { code: 'JOINME42' }), 'failed-precondition');
  });

  it('refuses expired invites, bad codes, and people already in a household', async () => {
    await invite({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await expectCode(call(acceptHouseholdInvite, 'carol', { code: 'JOINME42' }), 'failed-precondition');
    await expectCode(call(acceptHouseholdInvite, 'carol', { code: 'nope' }), 'invalid-argument');
    await expectCode(call(acceptHouseholdInvite, 'carol', { code: 'MISSING1' }), 'not-found');
    await invite();
    await expectCode(call(acceptHouseholdInvite, 'bob', { code: 'JOINME42' }), 'failed-precondition');
    await expectCode(call(acceptHouseholdInvite, null, { code: 'JOINME42' }), 'unauthenticated');
  });

  it('lets someone removed from another household join (a stale pointer does not count)', async () => {
    await invite();
    await db.doc('households/h2').set({ name: 'Old', ownerUid: 'zed', memberUids: ['zed'] });
    await db.doc('users/carol').set({ householdId: 'h2' }, { merge: true });
    await expect(call(acceptHouseholdInvite, 'carol', { code: 'JOINME42' })).resolves.toEqual({ householdId: 'h1' });
  });

  it('clears the profile pointer when someone is removed from a household', async () => {
    const run = (onMemberRemoved as unknown as { run: (e: unknown) => Promise<unknown> }).run;
    await run({ params: { hid: 'h1', uid: 'bob' } });
    expect((await db.doc('users/bob').get()).get('householdId')).toBeUndefined();
    await db.doc('users/carol').set({ householdId: 'h9' }, { merge: true });
    await run({ params: { hid: 'h1', uid: 'carol' } });
    expect((await db.doc('users/carol').get()).get('householdId')).toBe('h9');
  });

  it('cannot escalate to owner through the invite role', async () => {
    await invite({ role: 'owner' });
    await call(acceptHouseholdInvite, 'carol', { code: 'JOINME42' });
    expect((await db.doc('households/h1/members/carol').get()).get('role')).toBe('adult');
    expect((await db.doc('households/h1').get()).get('ownerUid')).toBe('alice');
  });
});

// ---------------------------------------------------------------- account deletion

describe('deleteAccountData', () => {
  it('requires a recent sign-in', async () => {
    await expectCode(call(deleteAccountData, 'bob', {}, { auth_time: now() - 3600 }), 'unauthenticated');
    expect((await db.doc('users/bob').get()).exists).toBe(true);
  });

  it('removes a member from a shared household and hands over ownership', async () => {
    await db.doc('users/alice/journal/j1').set({ title: 'Oats' });
    await db.doc('shareGrants/g1').set({ ownerUid: 'alice', proUid: 'pro' });
    await db.doc('assessments/a1').set({ clientUid: 'alice' });
    await db.doc('assessments/a2').set({ clientUid: 'bob' });
    await call(deleteAccountData, 'alice', {});
    const h = await db.doc('households/h1').get();
    expect(h.exists).toBe(true);
    expect(h.get('memberUids')).toEqual(['bob']);
    expect(h.get('ownerUid')).toBe('bob');
    expect((await db.doc('households/h1/members/alice').get()).exists).toBe(false);
    expect((await db.doc('users/alice').get()).exists).toBe(false);
    expect((await db.doc('users/alice/journal/j1').get()).exists).toBe(false);
    expect((await db.doc('shareGrants/g1').get()).exists).toBe(false);
    expect((await db.doc('assessments/a1').get()).exists).toBe(false);
    expect((await db.doc('assessments/a2').get()).exists).toBe(true);
  });

  it('never deletes a household the user is not a member of, whatever their profile says', async () => {
    // Alice removed Bob; Bob's profile still names h1 (or he set it himself).
    await db.doc('households/h1').update({ memberUids: ['alice'] });
    await db.doc('households/h1/lots/l1').set({ productName: 'Eggs' });
    await call(deleteAccountData, 'bob', {});
    expect((await db.doc('households/h1').get()).get('memberUids')).toEqual(['alice']);
    expect((await db.doc('households/h1/lots/l1').get()).exists).toBe(true);
    expect((await db.doc('users/bob').get()).exists).toBe(false);
  });

  it('removes grants and assessments on the professional side and AI usage records', async () => {
    await db.doc('shareGrants/alice__bob').set({ ownerUid: 'alice', professionalUid: 'bob' });
    await db.doc('assessments/a3').set({ clientUid: 'alice', professionalUid: 'bob' });
    await db.doc('aiUsage/u1').set({ uid: 'bob', task: 'chat' });
    await db.doc('aiUsage/u2').set({ uid: 'alice', task: 'chat' });
    await call(deleteAccountData, 'bob', {});
    expect((await db.doc('shareGrants/alice__bob').get()).exists).toBe(false);
    expect((await db.doc('assessments/a3').get()).exists).toBe(false);
    expect((await db.doc('aiUsage/u1').get()).exists).toBe(false);
    expect((await db.doc('aiUsage/u2').get()).exists).toBe(true);
  });

  it('deletes the household, its subcollections and receipt images when the last member leaves', async () => {
    await db.doc('households/h1').update({ memberUids: ['alice'] });
    await db.doc('households/h1/lots/l1').set({ productName: 'Eggs' });
    await getStorage().bucket().file('households/h1/receipts/r1/page_0').save(Buffer.from([0xff, 0xd8, 0xff]), { contentType: 'image/jpeg' });
    await call(deleteAccountData, 'alice', {});
    expect((await db.doc('households/h1').get()).exists).toBe(false);
    expect((await db.doc('households/h1/lots/l1').get()).exists).toBe(false);
    const [files] = await getStorage().bucket().getFiles({ prefix: 'households/h1/' });
    expect(files).toHaveLength(0);
  });
});

// ---------------------------------------------------------------- receipts

const extraction = (over: Partial<ReceiptExtraction> = {}): ReceiptExtraction => ({
  isReceipt: true, imageQuality: 'good', merchant: 'Maison Market', purchaseDate: new Date().toISOString().slice(0, 10), currency: 'CAD',
  subtotalCents: 479, taxCents: 0, totalCents: 479,
  lines: [{
    rawText: 'LG EGGS 12CT', name: 'Eggs', brand: null, category: 'dairy', isFood: true, quantity: 12, unit: 'piece',
    packageDescription: null, unitPriceCents: null, totalPriceCents: 479, storage: 'fridge', confidence: 0.95,
  }],
  ...over,
});

async function uploadedReceipt(id: string) {
  const path = `households/h1/receipts/${id}/page_0`;
  await getStorage().bucket().file(path).save(Buffer.from([0xff, 0xd8, 0xff, 0xe0]), { contentType: 'image/jpeg' });
  await db.doc(`households/h1/receipts/${id}`).set({ status: 'uploaded', pagePaths: [path], createdBy: 'alice' });
}

describe('processReceipt', () => {
  it('extracts, validates and stores lines for review without touching inventory', async () => {
    const fake = new FakeProvider(() => extraction());
    testHooks.provider = fake;
    await uploadedReceipt('r1');
    await expect(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r1' })).resolves.toEqual({ status: 'needsReview' });
    const r = await db.doc('households/h1/receipts/r1').get();
    expect(r.get('status')).toBe('needsReview');
    expect(r.get('lines')[0]).toMatchObject({ name: 'Eggs', matchedProductId: 'egg' });
    expect(r.get('total')).toEqual({ minor: 479, currency: 'CAD' });
    expect(r.get('aiModel')).toBe('fake:fake-1');
    expect(fake.calls[0].images?.[0].mimeType).toBe('image/jpeg');
    expect((await db.collection('households/h1/lots').get()).empty).toBe(true);
    // Idempotent: a second call does not run extraction again.
    await expect(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r1' })).resolves.toEqual({ status: 'skipped' });
    expect(fake.calls).toHaveLength(1);
    // Cost metadata only.
    const usage = await db.collection('aiUsage').get();
    expect(usage.size).toBe(1);
    expect(Object.keys(usage.docs[0].data()).sort()).not.toContain('prompt');
  });

  it('flags a receipt already imported as a duplicate', async () => {
    testHooks.provider = new FakeProvider(() => extraction());
    await uploadedReceipt('r1');
    await call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r1' });
    const fp = (await db.doc('households/h1/receipts/r1').get()).get('fingerprint');
    await db.doc(`households/h1/receiptFingerprints/${fp}`).set({ receiptId: 'r1' });
    await uploadedReceipt('r2');
    await expect(call(processReceipt, 'bob', { householdId: 'h1', receiptId: 'r2' })).resolves.toEqual({ status: 'duplicate' });
    expect((await db.doc('households/h1/receipts/r2').get()).get('duplicateOfReceiptId')).toBe('r1');
  });

  it('fails safely on non-receipts and provider errors, with nothing added', async () => {
    testHooks.provider = new FakeProvider(() => extraction({ isReceipt: false, lines: [] }));
    await uploadedReceipt('r1');
    await expect(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r1' })).resolves.toMatchObject({ status: 'failed', errorCode: 'not_a_receipt' });
    testHooks.provider = new FakeProvider(() => new Error('upstream 503'));
    await uploadedReceipt('r2');
    await expect(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r2' })).resolves.toMatchObject({ status: 'failed', errorCode: 'unavailable' });
    expect((await db.doc('households/h1/receipts/r2').get()).get('status')).toBe('failed');
  });

  it('rejects page paths outside the receipt folder', async () => {
    testHooks.provider = new FakeProvider(() => extraction());
    await db.doc('households/h1/receipts/r3').set({ status: 'uploaded', pagePaths: ['households/other/receipts/x/page_0'] });
    await expect(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r3' })).resolves.toMatchObject({ errorCode: 'bad_upload' });
  });

  it('requires membership and AI consent', async () => {
    await uploadedReceipt('r1');
    await expectCode(call(processReceipt, 'carol', { householdId: 'h1', receiptId: 'r1' }), 'permission-denied');
    await db.doc('users/alice/private/settings').set({ aiProcessingConsent: false });
    await expectCode(call(processReceipt, 'alice', { householdId: 'h1', receiptId: 'r1' }), 'failed-precondition');
    await expectCode(call(processReceipt, 'alice', { householdId: 'h1', receiptId: '../x' }), 'invalid-argument');
  });
});

// ---------------------------------------------------------------- chef

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

describe('chefRecommend', () => {
  it('filters recipes that conflict with allergens another member shared', async () => {
    let seen: StructuredRequest | undefined;
    testHooks.provider = new FakeProvider((req) => {
      seen = req;
      return { recipes: [recipe(), recipe({ title: 'Garlic rice', ingredients: [{ name: 'rice', quantity: 150, unit: 'g', preparation: null, optional: false }], rationale: 'Simple.' })] };
    });
    const res = (await call(chefRecommend, 'alice', { householdId: 'h1', count: 2 })) as { recipes: Array<{ title: string }>; filteredForSafety: number };
    expect(res.recipes.map((r) => r.title)).toEqual(['Garlic rice']);
    expect(res.filteredForSafety).toBe(1);
    expect(seen?.system).toContain('peanut');
  });

  it('asks for Canadian French when the app is in French', async () => {
    let seen: StructuredRequest | undefined;
    testHooks.provider = new FakeProvider((req) => {
      seen = req;
      return { recipes: [] };
    });
    await call(chefRecommend, 'alice', { householdId: 'h1', language: 'fr-CA' });
    expect(seen?.system).toContain('Canadian French');
    await call(chefRecommend, 'alice', { householdId: 'h1' });
    expect(seen?.system).toContain('Canadian English');
  });

  it('enforces the daily limit', async () => {
    testHooks.provider = new FakeProvider(() => ({ recipes: [] }));
    const day = new Date().toISOString().slice(0, 10);
    await db.doc(`rateLimits/alice_${day}`).set({ chef_recipes: 80 });
    await expectCode(call(chefRecommend, 'alice', { householdId: 'h1' }), 'resource-exhausted');
  });
});
