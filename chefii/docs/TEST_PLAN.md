# Test Plan

## Automated (in repo)

| Suite | Command | What it covers |
|---|---|---|
| Domain unit tests | `flutter test test/domain` | Units and conversions; consumption planner (FIFO, freezer last, preferred lot, shortfall, bridges, incompatible units); inventory repository (idempotency, concurrent double taps, atomic multi-product cooking, over-consumption clamp, undo, undo after use, correction confirms, mark-empty isolation, move and undo, status semantics); product matcher; command parser; allergen guard (exclusions, product tags, unknown status, restrictions); curated recipe integrity (catalogue references, nutrition completeness, derived tags); availability; dates and money |
| Data flow tests | `flutter test test/data` | Image validation by magic bytes; duplicate hash; receipt blocking lines; full import with exclusions, confirmation, review flags, raw text preserved, retry idempotency, no edits after import; cancelled receipts stay cancelled; cooking → one deduction → journal → leftovers; shopping list from plan (merged, net of stock); professional grants (scope, other viewers, revocation, audit, unverified rejection); glucose validation and units; store persistence |
| Widget smoke tests | `flutter test test/widget` | Session redirect rules; full onboarding through the UI (consent required, allergy capture, example kitchen); renders every route without exceptions or overflow at phone width; allergy-blocked recipe shows the disabled state; key routes at **160% text size** |
| Backend unit tests | `cd functions && npm test` | Receipt validation (clean, non-receipt, missing quantities, totals mismatch, non-food/discount/duplicates, dates/units); allergen parity with Dart; matcher parity; AI recipe screening and plausibility; meal nutrition from reference data; schema accept/reject; router (optional provider gating, image routing, schema rejection, non-retryable errors) |
| Security rules | `cd rules-tests && npm test` (runs the Firestore emulator) | 13 scenarios; see SECURITY_MODEL.md |
| Shared-data drift | `dart run tool/export_shared_data.dart --check` | Fails if the TypeScript catalogue/lexicon is stale |
| Static analysis | `flutter analyze`, `npx tsc --noEmit` | Lints, types |

CI: `.github/workflows/chefii.yml` runs all of the above on pushes and pull requests touching `chefii/`.

## To add before launch

1. **Device integration tests** (`integration_test/`) on iOS and Android simulators: camera permission denied/granted, document scanner, notification scheduling and tap-through deep links, voice input, TTS, App Check debug token.
2. **Emulator integration tests for callables** with the `FakeProvider` injected: idempotent `processReceipt`, duplicate fingerprints, consent and rate limit refusals, `deleteAccountData` removing everything, `acceptHouseholdInvite` single use and expiry.
3. **Storage rules tests** (size, type, page name, membership).
4. **Live AI evaluation set:** 50 real Canadian receipts (Loblaws, Metro, Sobeys, Costco, IGA, Farm Boy; English and French) with hand-labelled ground truth. Track line recall, quantity precision, price accuracy and false-food rate per model version. Gate model changes on no regression.
5. **Allergen red-team set:** 200 ingredient strings including brand names, French terms (e.g. "arachides", "lait", "noix") and hidden sources; must reach 100% recall for listed allergens.
6. **Accessibility:** TalkBack and VoiceOver walk-through of onboarding, receipt review, guided cooking and sharing; contrast audit of the dark theme.
7. **Performance:** cold start under 2 s on a mid-range Android device; kitchen list scrolls smoothly with 500 lots.
8. **Manual exploratory charters:** offline behaviour, two household members editing the same lot, timezone change during the morning routine, account deletion with a shared household.

## Release gates

All automated suites green; device suites green on the latest iOS and Android plus one older version (iOS 15, Android 7 / API 24); no P0/P1 defects; allergen red-team at 100% recall; clinical sign-off recorded (CLINICAL_SAFETY.md).
