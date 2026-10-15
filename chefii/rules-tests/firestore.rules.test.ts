import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp, writeBatch, collection, getDocs, query, where } from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

let env: RulesTestEnvironment;
const day = 86400_000;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-chefii',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'households/h1'), { name: 'Home', ownerUid: 'alice', memberUids: ['alice', 'bob'] });
    await setDoc(doc(db, 'households/h1/lots/l1'), { householdId: 'h1', productId: 'egg', quantity: { amount: 6, unit: 'piece' } });
    await setDoc(doc(db, 'households/h1/adjustments/a1'), { householdId: 'h1', lotId: 'l1' });
    await setDoc(doc(db, 'households/h1/operations/o1'), { householdId: 'h1', summary: 'Used 2 eggs' });
    await setDoc(doc(db, 'users/alice'), { displayName: 'Alice', isProfessional: false });
    await setDoc(doc(db, 'users/alice/journal/j1'), { title: 'Oats', eatenAt: Timestamp.fromMillis(Date.now() - day) });
    await setDoc(doc(db, 'users/alice/journal/old'), { title: 'Old', eatenAt: Timestamp.fromMillis(Date.now() - 90 * day) });
    await setDoc(doc(db, 'users/alice/glucose/g1'), { valueMmolL: 5.4, measuredAt: Timestamp.fromMillis(Date.now() - day) });
    await setDoc(doc(db, 'professionals/pro'), { displayName: 'Dr Pro', status: 'verified' });
    await setDoc(doc(db, 'professionals/pending'), { displayName: 'Pending', status: 'pending' });
  });
});

const as = (uid: string) => env.authenticatedContext(uid).firestore();

describe('households', () => {
  it('members can read and adjust the shared kitchen; others cannot', async () => {
    await assertSucceeds(getDoc(doc(as('bob'), 'households/h1/lots/l1')));
    await assertFails(getDoc(doc(as('mallory'), 'households/h1/lots/l1')));
    await assertSucceeds(updateDoc(doc(as('bob'), 'households/h1/lots/l1'), { quantity: { amount: 4, unit: 'piece' } }));
    await assertFails(updateDoc(doc(as('bob'), 'households/h1/lots/l1'), { quantity: { amount: -1, unit: 'piece' } }));
    await assertFails(deleteDoc(doc(as('alice'), 'households/h1/lots/l1')));
  });

  it('the ledger is append-only', async () => {
    await assertSucceeds(setDoc(doc(as('bob'), 'households/h1/adjustments/a2'), { householdId: 'h1' }));
    await assertFails(updateDoc(doc(as('bob'), 'households/h1/adjustments/a1'), { lotId: 'x' }));
    await assertFails(deleteDoc(doc(as('alice'), 'households/h1/adjustments/a1')));
  });

  it('operations can only be marked undone, once', async () => {
    await assertFails(updateDoc(doc(as('bob'), 'households/h1/operations/o1'), { summary: 'changed' }));
    await assertSucceeds(updateDoc(doc(as('bob'), 'households/h1/operations/o1'), { undoneByOperationId: 'undo_o1' }));
    await assertFails(updateDoc(doc(as('bob'), 'households/h1/operations/o1'), { undoneByOperationId: 'undo_again' }));
  });

  it('household creation must make the creator the sole owner-member', async () => {
    const db = as('carol');
    const batch = writeBatch(db);
    batch.set(doc(db, 'households/h2'), { name: 'C', ownerUid: 'carol', memberUids: ['carol'] });
    batch.set(doc(db, 'households/h2/members/carol'), { displayName: 'Carol', role: 'owner' });
    await assertSucceeds(batch.commit());
    await assertFails(setDoc(doc(as('dave'), 'households/h3'), { ownerUid: 'dave', memberUids: ['dave', 'alice'] }));
    await assertFails(setDoc(doc(as('dave'), 'households/h1/members/dave'), { displayName: 'Dave' }));
  });

  it('non-owners cannot add members; owners can only remove', async () => {
    await assertFails(updateDoc(doc(as('bob'), 'households/h1'), { memberUids: ['alice', 'bob', 'mallory'] }));
    await assertFails(updateDoc(doc(as('alice'), 'households/h1'), { memberUids: ['alice', 'bob', 'mallory'] }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'households/h1'), { memberUids: ['alice'] }));
  });
});

describe('private health data', () => {
  it('is invisible to other household members', async () => {
    await assertSucceeds(getDoc(doc(as('alice'), 'users/alice/journal/j1')));
    await assertFails(getDoc(doc(as('bob'), 'users/alice/journal/j1')));
    await assertFails(getDoc(doc(as('bob'), 'users/alice/glucose/g1')));
  });

  it('users cannot grant themselves professional status', async () => {
    await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { isProfessional: true }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice'), { displayName: 'Ali' }));
    await assertFails(updateDoc(doc(as('pending'), 'professionals/pending'), { status: 'verified' }));
  });

  it('server-only collections are closed', async () => {
    await assertFails(getDoc(doc(as('alice'), 'aiUsage/x')));
    await assertFails(setDoc(doc(as('alice'), 'rateLimits/alice_2026-10-15'), { receipt: 0 }));
  });
});

describe('professional sharing', () => {
  const grant = (over: Record<string, unknown> = {}) => ({
    ownerUid: 'alice',
    professionalUid: 'pro',
    categories: ['glucose'],
    rangeStart: Timestamp.fromMillis(Date.now() - 30 * day),
    expiresAt: Timestamp.fromMillis(Date.now() + 30 * day),
    status: 'active',
    ...over,
  });

  it('grants must target a verified professional with the canonical id', async () => {
    await assertSucceeds(setDoc(doc(as('alice'), 'shareGrants/alice__pro'), grant()));
    await assertFails(setDoc(doc(as('alice'), 'shareGrants/alice__pending'), grant({ professionalUid: 'pending' })));
    await assertFails(setDoc(doc(as('alice'), 'shareGrants/whatever'), grant()));
    await assertFails(setDoc(doc(as('mallory'), 'shareGrants/alice__pro'), grant()));
  });

  it('an active grant opens only the shared categories and time range', async () => {
    await setDoc(doc(as('alice'), 'shareGrants/alice__pro'), grant());
    await assertSucceeds(getDoc(doc(as('pro'), 'users/alice/glucose/g1')));
    await assertFails(getDoc(doc(as('pro'), 'users/alice/journal/j1')));
    await assertFails(getDoc(doc(as('other-pro'), 'users/alice/glucose/g1')));

    await updateDoc(doc(as('alice'), 'shareGrants/alice__pro'), { categories: ['journal'] });
    await assertSucceeds(getDoc(doc(as('pro'), 'users/alice/journal/j1')));
    await assertFails(getDoc(doc(as('pro'), 'users/alice/journal/old')), 'before rangeStart');
    await assertSucceeds(getDocs(query(collection(as('pro'), 'users/alice/journal'), where('eatenAt', '>=', Timestamp.fromMillis(Date.now() - 30 * day)))));
  });

  it('revoked or expired grants close access immediately', async () => {
    await setDoc(doc(as('alice'), 'shareGrants/alice__pro'), grant());
    await updateDoc(doc(as('alice'), 'shareGrants/alice__pro'), { status: 'revoked' });
    await assertFails(getDoc(doc(as('pro'), 'users/alice/glucose/g1')));
    await updateDoc(doc(as('alice'), 'shareGrants/alice__pro'), { status: 'active', expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await assertFails(getDoc(doc(as('pro'), 'users/alice/glucose/g1')));
  });

  it('professionals cannot edit grants; clients control assessments only by responding', async () => {
    await setDoc(doc(as('alice'), 'shareGrants/alice__pro'), grant());
    await assertFails(updateDoc(doc(as('pro'), 'shareGrants/alice__pro'), { expiresAt: Timestamp.fromMillis(Date.now() + 365 * day) }));
    await assertSucceeds(setDoc(doc(as('pro'), 'assessments/as1'), {
      grantId: 'alice__pro', clientUid: 'alice', professionalUid: 'pro', summary: 'Looks good', status: 'sharedWithClient',
    }));
    await assertFails(setDoc(doc(as('other-pro'), 'assessments/as2'), {
      grantId: 'alice__other-pro', clientUid: 'alice', professionalUid: 'other-pro', summary: 'x', status: 'sharedWithClient',
    }));
    await assertFails(updateDoc(doc(as('alice'), 'assessments/as1'), { summary: 'edited' }));
    await assertSucceeds(updateDoc(doc(as('alice'), 'assessments/as1'), { status: 'accepted', clientRespondedAt: Timestamp.now() }));
  });

  it('access logs are written by the professional and readable by the client', async () => {
    await setDoc(doc(as('alice'), 'shareGrants/alice__pro'), grant());
    await assertSucceeds(setDoc(doc(as('pro'), 'shareGrants/alice__pro/accessLog/x'), { viewerUid: 'pro', what: 'Glucose' }));
    await assertFails(setDoc(doc(as('mallory'), 'shareGrants/alice__pro/accessLog/y'), { viewerUid: 'mallory', what: 'x' }));
    await assertSucceeds(getDoc(doc(as('alice'), 'shareGrants/alice__pro/accessLog/x')));
    await assertFails(deleteDoc(doc(as('pro'), 'shareGrants/alice__pro/accessLog/x')));
  });
});
