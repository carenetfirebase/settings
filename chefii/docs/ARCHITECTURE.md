# Architecture

```
chefii/
  lib/
    main.dart                 bootstrap: demo or Firebase providers
    app/                      config, Riverpod providers, AppActions, router, app widget
    core/design/              tokens, theme, component library ("Quiet Luxury")
    core/services/            notifications, voice (STT/TTS), privacy-safe analytics
    domain/                   pure Dart: models, units, inventory planner, safety, nutrition, recipes
    data/                     DocStore (Firestore | memory), repositories, auth, AI gateway
    features/<area>/          screens grouped by product area
  functions/                  Cloud Functions (TypeScript): AI, receipts, accounts, invites
  firestore.rules, storage.rules, firestore.indexes.json, firebase.json
  rules-tests/                emulator tests for Firestore rules
  tool/export_shared_data.dart  generates functions/src/data/*.json from Dart
  test/                       unit, flow and widget tests
```

## Layers

1. **Domain (`lib/domain`)** — no Flutter, no Firebase. Units and conversions, models with explicit (de)serialisation, the consumption planner, allergen guard, nutrition calculator, product matcher, command parser, recipe availability, substitutions, evidence library. Fully unit-tested.
2. **Data (`lib/data`)** — the `DocStore` interface (`get`, `query`, `watch`, `set`, `delete`, `transaction`) with two implementations:
   - `FirestoreDocStore` (production; converts `Timestamp` ↔ UTC `DateTime` at the boundary),
   - `MemoryDocStore` (tests and demo mode; genuinely atomic serialised transactions, JSON persistence to SharedPreferences).
   Repositories are written once against `DocStore`, so the same code is tested in memory and runs on Firestore.
3. **Application (`lib/app`)** — Riverpod 3 providers (streams per user/household), `AppActions` (every mutation: binds user + household, mints idempotency keys, logs analytics), `go_router` configuration.
4. **Presentation (`lib/features`, `lib/core/design`)** — screens compose design-system components; no business logic beyond view state.

## Key decisions (details in DECISIONS.md)

- **Flutter 3.47 / Dart 3.13**, **Riverpod 3.4**, **go_router 18** with `StatefulShellRoute.indexedStack` (five tabs keep their stacks).
- **`material_ui` package** for Material widgets (go_router 18 builds its pages with it; mixing it with `flutter/material` splits theme lookups).
- **Hand-written immutable models** with `toMap`/`fromMap` — no code generation step, and the shape is visible in review.
- **Demo mode by default** (`--dart-define=CHEFII_BACKEND=firebase` for production) so the full product runs offline with clearly labelled sample AI.

## Inventory engine

See DATA_MODELS.md §Inventory. Summary:

- **Lots** (physical batches) are a projection of an **append-only ledger** of `InventoryAdjustment`s.
- Each user action is one **operation** whose id is the **idempotency key**; adjustment and new-lot ids derive from it (`{op}_a0`, `{op}_l0`), so retries are exact replays.
- Every mutation runs in **one transaction**: re-read candidate lots, plan, write lots + adjustments + operation. A repeated key returns the stored operation with `alreadyApplied: true`.
- **Never negative:** the planner caps takes at the recorded quantity; excess becomes a **discrepancy** shown to the user.
- **FIFO by date:** explicitly tapped lot → earliest confirmed date → earliest estimate → oldest purchase; freezer last.
- **Undo** appends inverse entries (`undo_{op}`), marks the original, clamps at zero and reports if stock was used since.
- **Unit safety:** conversions only within a dimension, or across through a product's density/per-piece bridge, which downgrades confidence to *estimated*.

Concurrency: Firestore transactions retry on contention; the memory store serialises transactions. The flow tests include 5 concurrent identical taps applying once.

## Receipt pipeline

```
device                                   Cloud Functions (northamerica-northeast1)
──────                                   ─────────────────────────────────────────
capture (doc scanner / camera / library)
validate type (magic bytes) & size
SHA-256 each page → duplicate check
create receipt doc (uploading)
upload to Storage households/{h}/receipts/{id}/page_n
mark uploaded ──────────────────────────► processReceipt (callable, App Check, auth,
                                           membership, AI consent, daily quota)
                                          txn: uploaded|failed → processing (idempotent)
                                          verify paths/type/size, download pages
                                          Gemini structured extraction (JSON schema)
                                          Ajv validation → deterministic checks:
                                            totals reconcile, units, discounts,
                                            duplicates, dates, non-food, confidence
                                          catalogue matching; fingerprint duplicate check
                                          write needsReview | failed | duplicate
watch receipt doc (live progress) ◄──────
review / correct / unknown / storage
confirm → InventoryRepository.addLots(op = receipt_{id}) → mark imported + fingerprint
```

Inventory is never changed server-side from AI output; the user's confirmation on the device is the only path, and it is idempotent.

## AI

`functions/src/ai/`: provider-neutral `AiProvider` (Gemini primary, OpenAI optional, Fake for tests) behind an `AiRouter` that:

- routes images only to the primary provider; conversation/recipes to OpenAI only when enabled *and* the user allowed it;
- validates output against the task schema (Ajv) and falls back on retryable failure or invalid output — it never "repairs" or fabricates;
- logs usage metadata (task, provider, model, latency, tokens, success) without content.

Client: `AiGateway` interface — `FirebaseAiGateway` (callables) and `DemoAiGateway` (curated library + labelled samples). AI recipes are re-screened by the client-side allergen guard and their nutrition recomputed from reference data.

Contracts: AI_CONTRACTS.md.

## Design system

Tokens in `core/design/tokens.dart` (porcelain, ivory, sage, forest, champagne, ink, muted; semantic success/warning/error/info with soft variants; 8-pt spacing; radii; 48 dp touch targets). Typography: Cormorant Garamond (headlines ≥ 22 pt, lining figures) + Inter (UI, data). Light theme is primary; dark theme provided. Components: `PremiumAppScaffold`, `EditorialPageHeader`, `PrimaryActionButton`, `SecondaryActionButton`, `LuxuryRecipeCard`, `IngredientCard`, `InventoryStatusBadge`, `NutritionSummaryCard`, `MealTimelineItem`, `MorningRoutineCard`, `ChefConversationBubble`, `EvidenceReferenceCard`, `DentalExposureCard`, `PermissionSelector`, `ProfessionalReviewCard`, `EmptyState`, `ErrorState`, `LoadingState`, `ConfirmActionSheet`, `QuantityStepper`, `PhotoCaptureOverlay`, `SearchFilterBar`, `BottomNavigationShell`, plus `FoodArtwork`, `TagPill`, `SoftCard`, `ToggleTile`, `ChoiceChipGroup`, `DemoBanner`.

Accessibility: status never by colour alone (icon + label), semantics labels on composite widgets, `liveRegion` for progress and errors, in-app text scale multiplies the system setting (clamped 0.85–2.0), reduce-motion honoured.

## Offline

Firestore offline persistence (100 MB cache) keeps the kitchen usable offline; client transactions require connectivity, so inventory writes made offline fail with a friendly message rather than queueing silently (see FEATURE_STATUS for the planned offline queue). Demo mode is fully offline.

## Environments

| Mode | How | Backend |
|---|---|---|
| Demo (default) | `flutter run` | MemoryDocStore + SharedPreferences; DemoAiGateway |
| Emulators | `--dart-define=CHEFII_BACKEND=firebase --dart-define=CHEFII_EMULATORS=true` | Firebase Emulator Suite |
| Production | `--dart-define=CHEFII_BACKEND=firebase` (+ real `firebase_options.dart`) | Firebase project in `northamerica-northeast1` |
