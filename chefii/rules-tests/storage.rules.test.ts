import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

// Storage rules read household membership from Firestore, so both emulators run.
let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-chefii',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: readFileSync('../storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});
afterAll(() => env.cleanup());

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
const page0 = 'households/h1/receipts/r1/page_0';

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'households/h1'), { name: 'Home', ownerUid: 'alice', memberUids: ['alice', 'bob'] });
    await uploadBytes(ref(ctx.storage(), 'households/h1/receipts/existing/page_0'), jpeg, { contentType: 'image/jpeg' });
  });
});

const store = (uid?: string) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();

describe('receipt images', () => {
  it('household members can upload receipt pages', async () => {
    await assertSucceeds(uploadBytes(ref(store('bob'), page0), jpeg, { contentType: 'image/jpeg' }));
    await assertSucceeds(uploadBytes(ref(store('alice'), 'households/h1/receipts/r1/page_4'), jpeg, { contentType: 'image/heic' }));
  });

  it('non-members and signed-out users cannot upload or read', async () => {
    await assertFails(uploadBytes(ref(store('mallory'), page0), jpeg, { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(store(), page0), jpeg, { contentType: 'image/jpeg' }));
    await assertFails(getBytes(ref(store('mallory'), 'households/h1/receipts/existing/page_0')));
    await assertFails(getBytes(ref(store(), 'households/h1/receipts/existing/page_0')));
  });

  it('members can read their household receipts', async () => {
    await assertSucceeds(getBytes(ref(store('bob'), 'households/h1/receipts/existing/page_0')));
  });

  it('only images, at most five pages, under 12 MB', async () => {
    await assertFails(uploadBytes(ref(store('bob'), page0), jpeg, { contentType: 'application/pdf' }));
    await assertFails(uploadBytes(ref(store('bob'), page0), jpeg, { contentType: 'text/html' }));
    await assertFails(uploadBytes(ref(store('bob'), 'households/h1/receipts/r1/page_5'), jpeg, { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(store('bob'), 'households/h1/receipts/r1/evil.svg'), jpeg, { contentType: 'image/jpeg' }));
    const big = new Uint8Array(12 * 1024 * 1024 + 1);
    await assertFails(uploadBytes(ref(store('bob'), page0), big, { contentType: 'image/jpeg' }));
  });

  it('receipt images are immutable from clients', async () => {
    await assertFails(uploadBytes(ref(store('alice'), 'households/h1/receipts/existing/page_0'), jpeg, { contentType: 'image/png' }));
    await assertFails(deleteObject(ref(store('alice'), 'households/h1/receipts/existing/page_0')));
  });

  it('everything else is closed', async () => {
    await assertFails(uploadBytes(ref(store('alice'), 'users/alice/avatar.jpg'), jpeg, { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(store('alice'), 'public/anything.jpg'), jpeg, { contentType: 'image/jpeg' }));
    await assertFails(getBytes(ref(store('alice'), 'households/h1/other/file')));
  });
});
