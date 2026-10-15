import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { CHAT_SYSTEM, CHEF_SYSTEM, kitchenContext, MEAL_SYSTEM, PROMPT_VERSION, RECEIPT_SYSTEM, SCAN_SYSTEM } from './ai/prompts';
import { nutritionForEstimate, screenRecipes } from './chef/recipes';
import {
  db, enforceRateLimit, FieldValue, fmtQty, householdDietary, makeRouter, mapProviderError, requireAiConsent, requireAuth,
  requireMember, Timestamp,
} from './common';
import { GEMINI_API_KEY, MAX_IMAGE_BYTES, MAX_RECEIPT_PAGES, OPENAI_API_KEY, REGION } from './config';
import { bestMatch } from './matching';
import { validateExtraction } from './receipts/validate';
import {
  AiRecipe, chatReplySchema, MealEstimate, mealEstimateSchema, ReceiptExtraction, receiptExtractionSchema, recipeListSchema,
  ScanResult, scanSchema,
} from './schemas';

const opts = { region: REGION, enforceAppCheck: true, secrets: [GEMINI_API_KEY, OPENAI_API_KEY], timeoutSeconds: 120, memory: '1GiB' as const };
const light = { region: REGION, enforceAppCheck: true };

// ------------------------------------------------------------------ receipts

/**
 * Extracts a receipt the client uploaded to Storage. Idempotent: only
 * receipts in `uploaded` (or `failed`, for retry) are processed, and the
 * status flip to `processing` happens in a transaction, so a double call
 * cannot run extraction twice. Inventory is NOT changed here — the user
 * reviews and confirms on the device.
 */
export const processReceipt = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const { householdId, receiptId } = (req.data ?? {}) as { householdId?: string; receiptId?: string };
  const hid = await requireMember(householdId, uid);
  if (typeof receiptId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(receiptId)) throw new HttpsError('invalid-argument', 'Invalid receipt.');
  const settings = await requireAiConsent(uid);
  const ref = db.doc(`households/${hid}/receipts/${receiptId}`);

  const pagePaths = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'Receipt not found.');
    const status = snap.get('status');
    if (status !== 'uploaded' && status !== 'failed') return null; // already handled
    tx.update(ref, { status: 'processing', progress: 0.2, updatedAt: FieldValue.serverTimestamp(), errorCode: FieldValue.delete(), errorMessage: FieldValue.delete() });
    return (snap.get('pagePaths') as string[]) ?? [];
  });
  if (pagePaths === null) return { status: 'skipped' };

  const fail = async (code: string, message: string) => {
    await ref.update({ status: 'failed', errorCode: code, errorMessage: message, updatedAt: FieldValue.serverTimestamp() });
    return { status: 'failed', errorCode: code };
  };

  try {
    await enforceRateLimit(uid, 'receipt');
    const prefix = `households/${hid}/receipts/${receiptId}/`;
    if (!pagePaths.length || pagePaths.length > MAX_RECEIPT_PAGES || pagePaths.some((p) => !p.startsWith(prefix))) {
      return await fail('bad_upload', 'The receipt photos are missing. Please capture it again.');
    }
    const bucket = getStorage().bucket();
    const images = [];
    for (const p of pagePaths) {
      const file = bucket.file(p);
      const [meta] = await file.getMetadata();
      if (Number(meta.size) > MAX_IMAGE_BYTES) return await fail('too_large', 'That photo is too large.');
      const contentType = String(meta.contentType ?? '');
      if (!/^image\/(jpeg|png|webp|heic|heif)$/.test(contentType)) return await fail('bad_type', 'Please use a photo (JPEG, PNG, HEIC or WebP).');
      const [buf] = await file.download();
      images.push({ mimeType: contentType, base64: buf.toString('base64') });
    }
    await ref.update({ progress: 0.5 });

    const router = makeRouter(uid, settings.allowOptionalAiProvider);
    const { data, response } = await router.run<ReceiptExtraction>({
      task: 'receipt',
      system: RECEIPT_SYSTEM,
      messages: [{ role: 'user', text: `Read this receipt (${images.length} page${images.length === 1 ? '' : 's'}, in order).` }],
      images,
      schema: receiptExtractionSchema,
      schemaName: 'receipt_extraction',
      temperature: 0,
    });
    await ref.update({ progress: 0.9 });

    const v = validateExtraction(data);
    if (!v.ok) return await fail(v.errorCode === 'not_a_receipt' ? 'not_a_receipt' : 'unreadable', v.message);

    if (v.fingerprint) {
      const fp = await db.doc(`households/${hid}/receiptFingerprints/${v.fingerprint}`).get();
      if (fp.exists && fp.get('receiptId') !== receiptId) {
        await ref.update({ status: 'duplicate', duplicateOfReceiptId: fp.get('receiptId'), fingerprint: v.fingerprint, updatedAt: FieldValue.serverTimestamp() });
        return { status: 'duplicate' };
      }
    }
    const money = (c: number | null) => (c === null ? FieldValue.delete() : { minor: c, currency: v.currency });
    await ref.update({
      status: 'needsReview',
      progress: 1,
      merchant: v.merchant ?? FieldValue.delete(),
      purchaseDate: v.purchaseDate ?? FieldValue.delete(),
      subtotal: money(v.subtotal),
      tax: money(v.tax),
      total: money(v.total),
      lines: v.lines,
      issues: v.issues,
      fingerprint: v.fingerprint ?? FieldValue.delete(),
      aiModel: `${response.provider}:${response.model}`,
      promptVersion: PROMPT_VERSION,
      isDemo: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status: 'needsReview' };
  } catch (e) {
    logger.error('processReceipt failed', { hid, receiptId, error: (e as Error).message });
    if (e instanceof HttpsError && e.code === 'resource-exhausted') return await fail('rate_limited', e.message);
    return await fail('unavailable', 'We couldn\'t read this receipt just now. Nothing was added — please try again.');
  }
});

// ------------------------------------------------------------------ chef

async function inventorySummary(hid: string) {
  const lots = await db.collection(`households/${hid}/lots`).where('depleted', '==', false).limit(200).get();
  return lots.docs.map((d) => ({ name: String(d.get('productName')), amount: fmtQty(d.get('quantity')) }));
}

export const chefRecommend = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const d = (req.data ?? {}) as Record<string, unknown>;
  const hid = await requireMember(d.householdId, uid);
  const settings = await requireAiConsent(uid);
  await enforceRateLimit(uid, 'chef_recipes');
  const dietary = await householdDietary(uid, hid);
  const count = Math.min(Math.max(Number(d.count ?? 3), 1), 5);
  const brief = [
    `Suggest ${count} recipes.`,
    d.mealType ? `Meal: ${d.mealType}.` : '',
    d.maxMinutes ? `Total time at most ${Number(d.maxMinutes)} minutes.` : '',
    `Servings: ${Math.min(Math.max(Number(d.servings ?? 2), 1), 16)}.`,
    Array.isArray(d.cuisines) && d.cuisines.length ? `Cuisines: ${d.cuisines.slice(0, 5).join(', ')}.` : '',
    d.useWhatIHave !== false ? 'Strongly prefer what is already in the kitchen.' : '',
    typeof d.nutritionFocus === 'string' ? `Nutrition focus: ${d.nutritionFocus.slice(0, 40)}.` : '',
    Array.isArray(d.exclusions) && d.exclusions.length ? `Also leave out: ${d.exclusions.slice(0, 10).join(', ')}.` : '',
    typeof d.prompt === 'string' ? `Request: ${d.prompt.slice(0, 300)}` : '',
  ].filter(Boolean).join(' ');
  const context = kitchenContext({
    inventory: await inventorySummary(hid),
    dietary: { ...dietary, dislikes: [...dietary.dislikes, ...(Array.isArray(d.exclusions) ? (d.exclusions as string[]).slice(0, 10) : [])] },
    equipment: Array.isArray(d.equipment) ? (d.equipment as string[]).slice(0, 10) : undefined,
  });
  try {
    const { data, response } = await makeRouter(uid, settings.allowOptionalAiProvider).run<{ recipes: AiRecipe[] }>({
      task: 'chef_recipes',
      system: `${CHEF_SYSTEM}\n\n${context}`,
      messages: [{ role: 'user', text: brief }],
      schema: recipeListSchema,
      schemaName: 'recipe_list',
      temperature: 0.7,
    });
    const screened = screenRecipes(data.recipes, dietary, `${response.provider}:${response.model}`);
    return { recipes: screened.recipes, rationales: screened.rationales, filteredForSafety: screened.filtered, provider: response.provider };
  } catch (e) {
    mapProviderError(e);
  }
});

export const chefChat = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const d = (req.data ?? {}) as { householdId?: string; messages?: Array<{ role: string; text: string }> };
  const hid = await requireMember(d.householdId, uid);
  const settings = await requireAiConsent(uid);
  await enforceRateLimit(uid, 'chat');
  const messages = (Array.isArray(d.messages) ? d.messages : [])
    .slice(-20)
    .filter((m) => typeof m?.text === 'string' && m.text.trim())
    .map((m) => ({ role: m.role === 'assistant' ? 'assistant' as const : 'user' as const, text: m.text.slice(0, 2000) }));
  if (!messages.length || messages[messages.length - 1].role !== 'user') throw new HttpsError('invalid-argument', 'Say something to your chef first.');
  const dietary = await householdDietary(uid, hid);
  try {
    const { data, response } = await makeRouter(uid, settings.allowOptionalAiProvider).run<{ text: string; recipes: AiRecipe[] }>({
      task: 'chat',
      system: `${CHAT_SYSTEM}\n\n${kitchenContext({ inventory: await inventorySummary(hid), dietary })}`,
      messages,
      schema: chatReplySchema,
      schemaName: 'chef_reply',
      temperature: 0.7,
    });
    const screened = screenRecipes(data.recipes, dietary, `${response.provider}:${response.model}`);
    const note = screened.filtered ? ' (I left out an idea that didn\'t suit your household\'s dietary needs.)' : '';
    return { text: `${data.text.slice(0, 2000)}${note}`, recipes: screened.recipes };
  } catch (e) {
    mapProviderError(e);
  }
});

// ------------------------------------------------------------------ scans & meals

function decodeImage(b64: unknown): { mimeType: string; base64: string } {
  if (typeof b64 !== 'string' || !b64) throw new HttpsError('invalid-argument', 'Missing image.');
  const buf = Buffer.from(b64, 'base64');
  if (buf.length > MAX_IMAGE_BYTES) throw new HttpsError('invalid-argument', 'That image is too large.');
  const mimeType = buf[0] === 0xff && buf[1] === 0xd8 ? 'image/jpeg' : buf[0] === 0x89 && buf[1] === 0x50 ? 'image/png' : buf.subarray(8, 12).toString() === 'WEBP' ? 'image/webp' : buf.subarray(4, 8).toString() === 'ftyp' ? 'image/heic' : '';
  if (!mimeType) throw new HttpsError('invalid-argument', 'Please use a photo.');
  return { mimeType, base64: b64 };
}

export const scanStorage = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const d = (req.data ?? {}) as { householdId?: string; imageBase64?: string; location?: string };
  await requireMember(d.householdId, uid);
  const settings = await requireAiConsent(uid);
  await enforceRateLimit(uid, 'scan');
  const image = decodeImage(d.imageBase64);
  try {
    const { data } = await makeRouter(uid, settings.allowOptionalAiProvider).run<ScanResult>({
      task: 'scan',
      system: SCAN_SYSTEM,
      messages: [{ role: 'user', text: `This is the ${d.location === 'freezer' || d.location === 'pantry' ? d.location : 'fridge'}. What food can you clearly see?` }],
      images: [image],
      schema: scanSchema,
      schemaName: 'storage_scan',
      temperature: 0,
    });
    if (!data.isFoodStorage) return { items: [], message: data.message ?? 'That doesn\'t look like a fridge, freezer or pantry.' };
    const items = data.items
      .filter((i) => i.confidence >= 0.3 && i.name.trim())
      .map((i) => ({
        name: i.name.trim().slice(0, 60),
        category: i.category,
        confidence: i.confidence,
        visibleCount: i.visibleCount !== null && i.visibleCount > 0 && i.visibleCount <= 60 ? i.visibleCount : null,
        productId: bestMatch(i.name, 0.6)?.product.id ?? null,
        note: i.note,
      }));
    return { items, message: data.message };
  } catch (e) {
    mapProviderError(e);
  }
});

export const estimateMeal = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const d = (req.data ?? {}) as { description?: string; imageBase64?: string };
  const description = typeof d.description === 'string' ? d.description.slice(0, 500) : '';
  if (!description && !d.imageBase64) throw new HttpsError('invalid-argument', 'Describe the meal or add a photo.');
  const settings = await requireAiConsent(uid);
  await enforceRateLimit(uid, 'meal_estimate');
  try {
    const { data } = await makeRouter(uid, settings.allowOptionalAiProvider).run<MealEstimate>({
      task: 'meal_estimate',
      system: MEAL_SYSTEM,
      messages: [{ role: 'user', text: description || 'What is in this meal?' }],
      images: d.imageBase64 ? [decodeImage(d.imageBase64)] : undefined,
      schema: mealEstimateSchema,
      schemaName: 'meal_estimate',
      temperature: 0,
    });
    const nutrition = nutritionForEstimate(data);
    return {
      title: data.title.slice(0, 80) || description,
      items: data.items.map((i) => i.name),
      nutrition,
      note: nutrition.completeness < 1 ? 'Some foods couldn\'t be matched to reference data, so this is a partial estimate.' : (data.note ?? 'Estimate only.'),
    };
  } catch (e) {
    mapProviderError(e);
  }
});

// ------------------------------------------------------------------ households

export const acceptHouseholdInvite = onCall(light, async (req) => {
  const uid = requireAuth(req);
  const code = String((req.data as { code?: string })?.code ?? '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6,12}$/.test(code)) throw new HttpsError('invalid-argument', 'That code doesn\'t look right.');
  const q = await db.collectionGroup('invites').where('code', '==', code).limit(1).get();
  if (q.empty) throw new HttpsError('not-found', 'Invite not found.');
  const inviteRef = q.docs[0].ref;
  const householdRef = inviteRef.parent.parent!;
  const user = await getAuth().getUser(uid);
  await db.runTransaction(async (tx) => {
    const inv = await tx.get(inviteRef);
    const profile = await tx.get(db.doc(`users/${uid}`));
    if (inv.get('used') === true) throw new HttpsError('failed-precondition', 'This invite has already been used.');
    if ((inv.get('expiresAt') as Timestamp).toMillis() < Date.now()) throw new HttpsError('failed-precondition', 'This invite has expired.');
    if (profile.get('householdId')) throw new HttpsError('failed-precondition', 'You already belong to a household.');
    tx.update(householdRef, { memberUids: FieldValue.arrayUnion(uid) });
    tx.set(householdRef.collection('members').doc(uid), {
      displayName: user.displayName ?? profile.get('displayName') ?? 'Member',
      role: inv.get('role') === 'member' ? 'member' : 'adult',
      joinedAt: FieldValue.serverTimestamp(),
      sharedAllergens: [],
    });
    tx.set(db.doc(`users/${uid}`), { householdId: householdRef.id }, { merge: true });
    tx.update(inviteRef, { used: true, usedBy: uid, usedAt: FieldValue.serverTimestamp() });
  });
  return { householdId: householdRef.id };
});

// ------------------------------------------------------------------ account

export const revokeSessions = onCall(light, async (req) => {
  const uid = requireAuth(req);
  await getAuth().revokeRefreshTokens(uid);
  return { ok: true };
});

/**
 * Deletes a user's data. Requires a recent sign-in (auth_time within 5 min).
 * Removes private records, grants, assessments about them, and the household
 * if they're the only member (else just their membership).
 */
export const deleteAccountData = onCall({ ...light, timeoutSeconds: 300 }, async (req) => {
  const uid = requireAuth(req);
  const authTime = Number(req.auth?.token.auth_time ?? 0) * 1000;
  if (Date.now() - authTime > 5 * 60_000) throw new HttpsError('unauthenticated', 'Please sign in again to delete your account.');
  const profile = await db.doc(`users/${uid}`).get();
  const hid = profile.get('householdId') as string | undefined;
  if (hid) {
    const hRef = db.doc(`households/${hid}`);
    const h = await hRef.get();
    const members: string[] = h.get('memberUids') ?? [];
    if (members.length <= 1) {
      await db.recursiveDelete(hRef);
      await getStorage().bucket().deleteFiles({ prefix: `households/${hid}/` }).catch(() => undefined);
    } else {
      const remaining = members.filter((m) => m !== uid);
      await hRef.update({ memberUids: remaining, ...(h.get('ownerUid') === uid ? { ownerUid: remaining[0] } : {}) });
      await hRef.collection('members').doc(uid).delete();
    }
  }
  const grants = await db.collection('shareGrants').where('ownerUid', '==', uid).get();
  for (const g of grants.docs) await db.recursiveDelete(g.ref);
  const assessments = await db.collection('assessments').where('clientUid', '==', uid).get();
  for (const a of assessments.docs) await a.ref.delete();
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.doc(`professionals/${uid}`).delete().catch(() => undefined);
  logger.info('account data deleted', { uidHash: uid.slice(0, 4) });
  return { ok: true };
});

// ------------------------------------------------------------------ professionals

/** Admin-only: confirm a professional's registration after manual review. */
export const verifyProfessional = onCall(light, async (req) => {
  requireAuth(req);
  if (req.auth?.token.admin !== true) throw new HttpsError('permission-denied', 'Admins only.');
  const { proUid, approve } = (req.data ?? {}) as { proUid?: string; approve?: boolean };
  if (typeof proUid !== 'string') throw new HttpsError('invalid-argument', 'proUid required');
  const ref = db.doc(`professionals/${proUid}`);
  if (!(await ref.get()).exists) throw new HttpsError('not-found', 'No application.');
  const inviteCode = `RD${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
  await ref.update(approve ? { status: 'verified', verifiedAt: FieldValue.serverTimestamp(), inviteCode } : { status: 'rejected' });
  const user = await getAuth().getUser(proUid);
  await getAuth().setCustomUserClaims(proUid, { ...(user.customClaims ?? {}), professional: approve === true });
  return { ok: true, inviteCode: approve ? inviteCode : null };
});
