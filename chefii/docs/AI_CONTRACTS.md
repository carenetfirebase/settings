# AI Contracts

All AI calls are server-side callables in `functions/src/index.ts` (region `northamerica-northeast1`, App Check enforced, Firebase Auth required, household membership checked, **explicit AI-processing consent required**, per-user daily quotas). Provider keys are Secret Manager secrets (`GEMINI_API_KEY`, `OPENAI_API_KEY`) and never reach devices.

Schemas: `functions/src/schemas.ts`. They use the JSON-Schema subset accepted by both Gemini `responseJsonSchema` and OpenAI strict `json_schema` (all properties required, nullability via type unions, no `pattern`). After generation, output is re-validated with Ajv; failures are **rejected** (next provider tried), never patched.

## Providers and routing

| Task | Primary | Optional | Notes |
|---|---|---|---|
| `receipt` | Gemini (vision model) | — | images never go to the optional provider |
| `scan` | Gemini (vision) | — | |
| `meal_estimate` | Gemini | — | model identifies foods/grams only; nutrition computed from reference data |
| `chef_recipes` | Gemini | OpenAI (if `OPENAI_ENABLED` and user allows) | fallback to Gemini on retryable error or invalid output |
| `chat` | Gemini | OpenAI (same rule) | |

Model ids are deploy-time params (`GEMINI_MODEL`, `GEMINI_VISION_MODEL`, `OPENAI_MODEL`) with **no defaults**, so a deploy forces choosing current ids from provider docs. The OpenAI provider sets `store: false`.

The app is fully functional with OpenAI disabled.

## Callables

### `processReceipt({householdId, receiptId}) → {status}`
- Idempotent: transitions `uploaded|failed → processing` in a transaction; other states return `skipped`.
- Validates Storage paths (`households/{hid}/receipts/{id}/`), content type, size ≤ 8 MB, ≤ 5 pages.
- Output written to the receipt doc: `status: needsReview|failed|duplicate`, `lines`, `issues`, money fields, `fingerprint`, `aiModel`, `promptVersion`.
- **Never** changes inventory.

Extraction schema (abridged):
```json
{ "isReceipt": bool, "imageQuality": "good|blurry|dark|cut_off|partial",
  "merchant": str|null, "purchaseDate": "YYYY-MM-DD"|null, "currency": str|null,
  "subtotalCents": int|null, "taxCents": int|null, "totalCents": int|null,
  "lines": [{ "rawText": str, "name": str, "brand": str|null, "category": enum, "isFood": bool,
              "quantity": num|null, "unit": enum|null, "packageDescription": str|null,
              "unitPriceCents": int|null, "totalPriceCents": int|null,
              "storage": "fridge|freezer|pantry|custom", "confidence": 0..1 }] }
```
Deterministic post-processing (`receipts/validate.ts`): quantity only kept when printed + parseable (else confidence ≤ 0.6 and an issue), unknown names ≤ 0.3, discounts and non-food excluded, duplicate lines flagged, totals reconciled within 2¢ (mismatch lowers all confidences ≤ 0.85 and raises `totals_mismatch`), future/implausible dates dropped, merchant/date/total fingerprint for duplicate receipts.

### `chefRecommend(ChefRequest) → {recipes, rationales, filteredForSafety, provider}`
Request: `householdId, prompt?, mealType?, maxMinutes?, servings, cuisines[], useWhatIHave, equipment[], nutritionFocus?, exclusions[], count ≤ 5`. Context sent to the model: active inventory names/amounts (≤ 80), merged household dietary profile (allergies, intolerances, restrictions, dislikes). No names, emails or health records.

Recipe schema: title, summary, cuisine, mealTypes, servings 1–16, prep/cook minutes, difficulty, equipment, ingredients (name, quantity|null, unit|null, preparation|null, optional), steps (text, timerMinutes|null, timerLabel|null, tip|null), rationale, storageNotes|null.

Post-processing (`chef/recipes.ts`): plausibility checks, catalogue matching (productId), **allergen/restriction screening with the shared lexicon — conflicting recipes are removed**, conversion to the app's `Recipe` map (`origin: "ai"`, `aiModel`). The client screens again and recomputes nutrition from reference data when ≥ 70% of ingredients map.

### `chefChat({householdId, messages[≤20]}) → {text, recipes}`
Same safety pipeline; replies note when an idea was left out for dietary reasons.

### `scanStorage({householdId, imageBase64, location}) → {items, message}`
Items: `name, category, confidence, visibleCount|null, productId|null, note|null`. Prompt and post-processing forbid invented items and estimated volumes; `visibleCount` only for clearly countable items (≤ 60), confidence < 0.3 dropped. Nothing is added until the user confirms each item and enters amounts.

### `estimateMeal({description?, imageBase64?}) → {title, items, nutrition, note}`
The model lists foods and gram estimates only. Nutrition = Σ catalogue reference values (match score ≥ 0.65; weaker matches are counted as unknown and lower `completeness`).

## Prompts

`functions/src/ai/prompts.ts`, versioned (`PROMPT_VERSION`). Shared rules: structured output only; never invent items or quantities; no medical, weight-loss or disease claims; metric units; safe internal cooking temperatures.

## Demo gateway

`lib/data/ai/demo_ai_gateway.dart` returns a **labelled sample receipt** and **labelled sample scan** (every screen shows a Demo banner and "your photo was not analysed"), ranks curated recipes against real inventory, and estimates meals from reference data. It never presents sample output as analysis of the user's content.

## Usage logging

`aiUsage` documents: `uid, task, provider, model, ok, latencyMs, inputTokens?, outputTokens?, errorKind?, at`. No prompts, images or outputs are stored. See OPERATING_COSTS.md.

## Shared data

`tool/export_shared_data.dart` generates `functions/src/data/catalog.json` and `allergens.json` from the Dart sources; `--check` fails CI if they're stale. Parity tests exist on both sides (Dart `domain_services_test.dart`, TS `backend.test.ts`).
