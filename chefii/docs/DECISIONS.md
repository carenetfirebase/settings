# Decisions

Format: decision, why, consequences. Most recent last.

1. **Separate `chefii/` directory and branch.** The repository contained an unrelated Python investment-research project. Chefii lives in `chefii/` on `claude/chefii-flutter-app`, leaving the existing work untouched.
2. **Flutter 3.47.7 (stable), Dart 3.13.** Latest stable at build time.
3. **Riverpod 3 for state.** Compile-safe dependency graph, easy test overrides (the whole app runs on a `ProviderContainer` with in-memory overrides in widget tests).
4. **go_router 18 with `StatefulShellRoute.indexedStack`.** Preserves each tab's stack; deep links; redirect guards for auth and onboarding.
5. **`material_ui` package instead of `flutter/material`.** go_router 18 builds pages with `material_ui`; mixing the two splits `Theme.of` lookups.
6. **Hand-written immutable models.** No build_runner step; serialisation is explicit and reviewable. Trade-off: more boilerplate.
7. **`DocStore` abstraction over Firestore.** Repositories are tested against a real transactional in-memory store and run unchanged on Firestore; it also enables a complete offline demo mode.
8. **Demo mode by default.** Without credentials the product still runs end to end. Every sample AI output is labelled on screen (directive: never present fake responses as real).
9. **Inventory as an append-only ledger with idempotent operations.** Accuracy, auditability, safe retries and undo. Lots are a projection.
10. **Client-side transactions for inventory, server-side for AI.** Inventory changes are user-confirmed and need a fast response; rules enforce append-only and non-negative invariants. AI and secrets stay server-side.
11. **No `IngredientReservation` collection.** A cooking session's planned consumptions act as the reservation; deduction happens once on confirmation. Avoids stale holds when sessions are abandoned.
12. **Deterministic safety layers around AI.** Allergen guard on server and device; nutrition from reference data, not model numbers; schema validation that rejects rather than repairs.
13. **One lexicon and catalogue, exported to TypeScript.** `tool/export_shared_data.dart` plus a CI drift check prevent client/server divergence.
14. **Model ids without defaults.** Model names change quickly; forcing a deliberate choice at deploy avoids shipping a deprecated or wrong model.
15. **Gemini primary, OpenAI optional.** Per the directive. Images never go to the optional provider; the user can disable it.
16. **Apple sign-in through `FirebaseAuth.signInWithProvider`.** Removed the separate `sign_in_with_apple` package (fewer dependencies).
17. **Fonts bundled (Cormorant Garamond, Inter, SIL OFL).** No runtime font fetching (privacy, offline). Serif only for headlines ≥ 22 pt, with lining figures; Inter for data.
18. **Illustrations instead of photos.** No licensed photography yet; generated food photos must not be presented as the user's dish. `FoodArtwork` is labelled "Illustration" for screen readers.
19. **Canadian data residency (`northamerica-northeast1`).**
20. **Analytics opt-in with a parameter allow-list.**
21. **Receipt matching threshold 0.75; meal-nutrition matching threshold 0.65.** Raised after a test showed "mystery sauce" matching "soy sauce" at 0.5: a wrong nutrient match is worse than an unknown one.
22. **Monetisation deferred.** Per the directive; the Membership screen is informational.
23. **Platform document scanner (`cunning_document_scanner`).** Uses VisionKit (iOS) and ML Kit (Android) for edge detection and cropping, with plain camera and library fallback.
24. **Self-hosted CanvasKit for web builds (`--no-web-resources-cdn`).** No third-party CDN dependency for the professional portal.
