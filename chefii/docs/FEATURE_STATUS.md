# Feature Status

Status as of 2026-10-15, branch `claude/chefii-flutter-app`.

**Legend:** ✅ Done and tested · 🟡 Works, with the stated limitation · 🔴 Not built · ⚠️ Needs external setup or review before launch

"Tested" means automated tests: Dart unit/flow tests (`test/domain`, `test/data`), widget smoke tests that onboard a user and render every route (`test/widget`), TypeScript unit tests (`functions`), and Firestore rules tests in the emulator (`rules-tests`).

## What has been verified in this environment

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | 57 tests passing |
| `functions`: `tsc` + `vitest` | Builds; 17 tests passing |
| Firestore rules (emulator) | 13 tests passing |
| `flutter build web --release` | Builds; key screens screenshot-checked in Chromium at 390×844 |
| iOS / Android builds | ⚠️ **Not verified here** (no Xcode or Android SDK in this container). Native config is written but must be built and tested on devices. |
| Live AI providers | ⚠️ **Not called.** The router, schemas, validation and safety screening are tested with a fake provider; real Gemini/OpenAI calls need keys and model ids. |
| Firebase project | ⚠️ Not configured: `lib/firebase_options.dart` is a placeholder until `flutterfire configure` is run. |

## Core engines

| Capability | Status | Notes |
|---|---|---|
| Units and conversions | ✅ | Bridged conversions are flagged as estimates |
| Inventory ledger: lots, immutable adjustments, operations | ✅ | Idempotent, atomic, never negative, FIFO by date, freezer last |
| Undo (consume, intake, move, receipt import) | ✅ | Clamps at zero and reports when stock was used since |
| Concurrency and double taps | ✅ | Test runs 5 concurrent identical requests; applies once |
| Inventory statuses (confirmed, estimated, needs review, depleted, past recorded date) | ✅ | |
| Natural-language commands ("I used two eggs") | ✅ | Deterministic offline parser; never assumes an amount for uncountable items |
| Voice input | 🟡 | `speech_to_text`; untested on device; falls back to typing |
| Allergen and restriction guard (Canadian priority allergens + gluten) | ✅ | Dart and TS parity tests |
| Nutrition from reference data, with completeness | ✅ | ⚠️ Values need dietitian review |
| Product matching (receipt abbreviations) | ✅ | |
| Recipe availability against stock | ✅ | |
| Substitutions (curated, safety-checked) | ✅ | |

## Screens 01–80

| Area | Status | Limitations |
|---|---|---|
| 01–08 Onboarding | ✅ | Apple/Google sign-in need Firebase and device testing ⚠️; join by invite code works in online mode only |
| 09–11 Today | ✅ | |
| 12 Capture receipt | 🟡 | Platform document scanner (edge detection) on iOS/Android, untested on device; camera/library fallback |
| 13 Preview | 🟡 | Rotate, retake, multi-page, remove; **no manual crop** (the document scanner crops) |
| 14–20 Processing → import | ✅ (demo) / ⚠️ (live) | Full flow tested with the demo extractor; live extraction depends on Gemini |
| 21–25, 27–28 Kitchen | ✅ | Custom storage locations 🔴 (three defaults only). Add Product: optional photo 🔴. Barcodes only resolve to products this household has already named (no external barcode database) |
| 26 Fridge scan | 🟡 | Demo shows labelled samples; live path needs Gemini |
| 29–33 AI Chef | ✅ (demo) / ⚠️ (live) | Demo uses the curated library (20 recipes) |
| 34–38 Cooking | ✅ | Screen-awake (wakelock) 🔴; timers alert via local notification (untested on device) |
| 39–44 Mornings | 🟡 | Android alarm-clock mode and iOS time-sensitive notifications; iOS AlarmKit native bridge 🔴; untested on device |
| 45–49 Plan & shopping | ✅ | Unit pricing comes only from scanned receipts ("last paid") |
| 50–52 Nutrition, journal, spending | ✅ | Waste value in dollars 🔴 (counts only) |
| 53–57 Discover & rhythm | ✅ | Reminder snooze action buttons 🔴 |
| 58–60 Glucose | ✅ | Health app import (HealthKit / Health Connect) 🔴 |
| 61–66 Intelligence, evidence, Smile & Food | ✅ | ⚠️ Evidence is internal draft pending professional review |
| 67–70 Professionals | ✅ | Professional verification is manual (admin callable); web portal not separately hardened |
| 71–74, 76–80 Account | ✅ | French UI 🔴 (option shown as "coming soon"); dark theme exists but has not been visually QA'd |
| 75 Membership | 🟡 by design | Informational only; billing deferred per the directive |

## Backend

| Capability | Status |
|---|---|
| `processReceipt` (idempotent, validated, duplicate fingerprint) | ✅ logic / ⚠️ not emulator-integrated |
| `chefRecommend`, `chefChat`, `scanStorage`, `estimateMeal` | ✅ logic / ⚠️ needs live keys |
| AI router: per-task routing, fallback, schema rejection, usage logging | ✅ |
| Rate limits, AI consent check, App Check enforcement | ✅ (code) / ⚠️ App Check registration |
| `acceptHouseholdInvite`, `revokeSessions`, `deleteAccountData`, `verifyProfessional` | 🟡 written and type-checked, not integration-tested |
| Firestore rules | ✅ emulator-tested |
| Storage rules | 🟡 written, not emulator-tested |
| Indexes, TTL | ✅ declared |

## Not started

- Subscriptions and billing (deferred by design).
- Offline write queue for inventory (writes need connectivity; reads work offline).
- Spreadsheet export (optional per the directive; JSON export exists).
- Licensed food photography (illustrations are used and labelled as such).
- Push notifications from the server (receipt-ready notices are written in-app; FCM not wired).
- Automated end-to-end device tests (integration_test on iOS/Android).

## Original directive

The directive was cut off partway through §8 ("11. Confirmed purchase…"). Later sections, if any, were not received; everything above is based on §0–§8.
