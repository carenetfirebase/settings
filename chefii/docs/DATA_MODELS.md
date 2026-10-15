# Data Models

Firestore is the source of truth. Models live in `lib/domain/models/` with explicit `toMap`/`fromMap`; paths in `lib/data/paths.dart`. Timestamps are stored as UTC (`Timestamp` in Firestore, converted to `DateTime` at the `DocStore` boundary). Calendar dates without a time (use-by dates, plan days) are ISO `yyyy-MM-dd` strings to avoid time-zone drift. Money is integer **minor units** plus ISO currency.

## Ownership

```
households/{hid}                      shared — members only
  members/{uid}                       role, sharedAllergens (opt-in)
  invites/{code}                      single-use, 7-day
  products/{productId}                household catalogue (incl. barcodes)
  lots/{lotId}                        InventoryLot (projection)
  adjustments/{adjId}                 InventoryAdjustment (append-only)
  operations/{opId}                   InventoryOperation (idempotency key)
  receipts/{receiptId}                PurchaseReceipt + ReceiptLineItem[]
  receiptFingerprints/{fp}            duplicate detection
  recipes/{id}                        saved/AI recipes
  cookingSessions/{id}                CookingSession
  mealPlan/{id}                       MealPlanEntry
  shoppingItems/{id}                  ShoppingItem

users/{uid}                           private — owner only (+ granted professionals, read-only)
  private/dietary                     DietaryProfile (allergies, intolerances, restrictions, dislikes)
  private/wellness                    WellnessPreferences
  private/settings                    AppSettings (AI consent, analytics consent, text scale…)
  private/morningRoutine              MorningRoutine
  journal/{id}                        MealConsumption
  glucose/{id}                        GlucoseEntry
  oralExposures/{id}                  OralExposureEvent
  concerns/{id}                       UserConcern
  consents/{id}                       ConsentRecord (append-only)
  audit/{id}                          AuditEvent (append-only)
  notifications/{id}, favourites/{recipeId}, feedback/{id}

shareGrants/{ownerUid}__{proUid}      ShareGrant (deterministic id for rules)
  accessLog/{id}                      professional views, readable by the owner
professionals/{uid}                   ProfessionalProfile (status set server-side)
assessments/{id}                      ProfessionalAssessment
aiUsage/{id}, rateLimits/{uid_day}    server only (no content)
```

A household member never gains access to another member's journal, glucose, concerns, Smile & Food log or professional feedback. Only allergens a member chooses to share are visible to the household, so shared meals stay safe.

## Model reference

| Directive model | Implementation |
|---|---|
| UserProfile | `profile.dart › UserProfile` |
| Household / HouseholdMember | `profile.dart` |
| DietaryPreference / AllergyRestriction | `profile.dart › DietaryProfile` (with `DisclosureStatus`) |
| FoodProduct / ProductAlias | `inventory.dart › FoodProduct.aliases` |
| PurchaseReceipt / ReceiptLineItem | `receipt.dart` |
| InventoryLot / InventoryAdjustment | `inventory.dart` (+ `InventoryOperation`) |
| StorageLocation | `inventory.dart` (fridge, freezer, pantry defaults) |
| Recipe / RecipeIngredient / RecipeStep / RecipeSubstitution / RecipeNutrition | `recipe.dart`, `nutrition.dart › NutrientProfile` |
| CookingSession / IngredientConsumption | `meals.dart` |
| IngredientReservation | not persisted separately: the session's planned consumptions act as the reservation until confirmation (see DECISIONS) |
| MealConsumption | `meals.dart` |
| LeftoverBatch | an `InventoryLot` with `source = leftover`, `category = prepared`, `preparedFromRecipeId` |
| MealPlan / MealReminder / MorningRoutine | `planning.dart`; reminders in `AppSettings.mealReminders` |
| ShoppingList / ShoppingItem | `planning.dart` (one list per household) |
| NutritionSnapshot | computed on read from the journal (`dailyAverage`), not stored |
| NutrientReference / EvidenceSource / EvidenceClaim | `nutrition.dart`, `health.dart`, `domain/nutrition/evidence_library.dart` |
| UserConcern / OralExposureEvent / GlucoseEntry | `health.dart` |
| ProfessionalProfile / ShareGrant / ProfessionalAssessment | `professional.dart` |
| ConsentRecord / AuditEvent | `profile.dart`, `professional.dart` |
| NotificationPreference | `AppSettings` (quiet hours, meal reminders) |
| AIUsageEvent | server `aiUsage` collection (`functions/src/ai/router.ts › UsageEvent`) |

## Inventory

### InventoryLot

| Field | Meaning |
|---|---|
| `productId`, `productName`, `category` | identity (denormalised name for display) |
| `quantity`, `initialQuantity` | `{amount, unit}` — unit never changes for a lot |
| `locationId` | fridge / freezer / pantry |
| `acquiredAt` | UTC |
| `useByDate` | date **actually printed/confirmed** (ISO date) |
| `estimatedBestBefore` | **estimate** from typical shelf life, kept separate |
| `source` | receipt, manual, barcode, scan, correction, transfer, leftover, returned, demo |
| `provenance` | `{source, confidence 0..1, model?, raw?}` — raw receipt text preserved |
| `needsReview`, `depleted`, `version` | review flag, query helper, mutation counter |

### Status (display only, never a safety claim)

`depleted` (≤ 0) → `pastRecordedDate` (confirmed date passed) → `needsReview` (flag or confidence < 0.6) → `estimated` (confidence < 0.95) → `confirmed`.

### InventoryAdjustment (immutable)

`operationId, lotId, productId, type (intake|consume|discard|correction|transferIn|transferOut|reversal), delta, quantityBefore, quantityAfter, createdAt, createdBy, reason, reversesAdjustmentId`.

### InventoryOperation

Document id = idempotency key. `kind, adjustmentIds, lotIdsCreated, summary, discrepancies, undoneByOperationId, undoesOperationId`. Key formats: `adj_*`, `cmd_*`, `receipt_{receiptId}`, `cook_{sessionId}`, `leftover_{sessionId}`, `undo_{opId}`, `example_kitchen_{hid}`.

### Units

`lib/domain/units/units.dart`: mass (mg, g, kg, oz, lb), volume (ml, L, tsp 5 ml, tbsp 15 ml, cup 250 ml — Canadian metric cup), count (piece, dozen). Cross-dimension conversion only through a product's `gramsPerMl` / `gramsPerPiece` bridge; such results are flagged as estimates. Arithmetic rounds to 3 decimals.

## Indexes

`firestore.indexes.json`: lots (productId, depleted), adjustments (productId, createdAt desc), shareGrants (ownerUid, createdAt desc), assessments (clientUid|professionalUid, createdAt desc), professionals (inviteCode, status), collection-group `invites.code`, TTL on `rateLimits.expiresAt`.

## Migrations

Every `fromMap` tolerates missing optional fields with defaults (e.g. `initialQuantity` falls back to `quantity`). Breaking changes will bump a `schemaVersion` field per collection and run an idempotent migration Cloud Function; none required yet.
