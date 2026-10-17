# Feature Status

Status as of 2026-10-15, branch `claude/chefii-flutter-app`.

**Legend:** ✅ Done and tested · 🟡 Works, with the stated limitation · 🔴 Not built · ⚠️ Needs external setup or review before launch

"Tested" means automated tests: Dart unit/flow tests (`test/domain`, `test/data`), widget smoke tests that onboard a user and render every route (`test/widget`), TypeScript unit tests (`functions`), and Firestore rules tests in the emulator (`rules-tests`).

## What has been verified in this environment

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` | 333 tests passing (incl. allergen red-team set, accessibility guidelines, French at 100–200% text, reduce-motion cooking) |
| `functions`: `tsc` + `vitest` | Builds; 213 unit tests + 18 callable integration tests (emulators) passing |
| Firestore + Storage rules (emulator) | 25 tests (19 Firestore, 6 Storage) |
| `flutter build web --release` | Builds; key screens screenshot-checked in Chromium at 390×844 |
| iOS / Android builds | Built in GitHub Actions (Android debug APK + release AAB on Ubuntu; iOS release no-codesign + simulator on macOS). |
| On-device tests | The real app runs on an iPhone simulator and an Android API 34 emulator in CI (`integration_test/app_test.dart`): onboarding with an allergy, Today, guided cooking, kitchen, switching to French. ⚠️ Not yet run on physical phones. |
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
| Allergen and restriction guard (Canadian priority allergens + gluten) | ✅ | English + Canadian French label terms, accent folding; shared red-team set run on client and server |
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
| 21–25, 27–28 Kitchen | ✅ | Custom storage places ✅ (add/rename/remove; freezer-kind places used last). Add Product: optional photo 🔴 (post-launch). Barcodes only resolve to products this household has already named (no external barcode database) |
| 26 Fridge scan | 🟡 | Demo shows labelled samples; live path needs Gemini |
| 29–33 AI Chef | ✅ (demo) / ⚠️ (live) | Demo uses the curated library (20 recipes) |
| 34–38 Cooking | ✅ | Screen stays awake during guided cooking; timers alert via local notification (untested on device) |
| 39–44 Mornings | 🟡 | Android alarm-clock mode and iOS time-sensitive notifications; iOS AlarmKit native bridge 🔴; untested on device |
| 45–49 Plan & shopping | ✅ | Unit pricing comes only from scanned receipts ("last paid") |
| 50–52 Nutrition, journal, spending | ✅ | Waste value in dollars 🔴 (counts only) |
| 53–57 Discover & rhythm | ✅ | Reminders and morning alarm have a "Snooze 10 min" action (untested on device) |
| 58–60 Glucose | ✅ | Health app import (HealthKit / Health Connect) 🔴 |
| 61–66 Intelligence, evidence, Smile & Food | ✅ | ⚠️ Evidence is internal draft pending professional review |
| 67–70 Professionals | ✅ | Professional verification is manual (admin callable); web portal not separately hardened |
| 71–74, 76–80 Account | ✅ | Language: same as device / English / Français (Canada) |
| 75 Membership | 🟡 by design | Informational only; billing deferred per the directive |

## Language, accessibility and appearance

| Capability | Status | Notes |
|---|---|---|
| Canadian French interface | ✅ | ≈1,600 strings; CI fails on any untranslated string or hard-coded English. ⚠️ Native-speaker review list in FRENCH_REVIEW.md |
| French food names, Québec receipts, French voice commands | ✅ | Catalogue in French; matcher folds accents; parser understands Québec French |
| French recipes and evidence notes | ✅ | Allergen detection must be identical in both languages (test) |
| AI replies in French | ✅ | Chef, chat, meal titles |
| Accessibility | ✅ | Automated tap-target, label and WCAG contrast checks on 20 screens, light and dark; 200% text; ⚠️ manual VoiceOver/TalkBack pass still needed |
| Dark mode | ✅ | Screenshot-checked; illustrations dimmed |

## Backend

| Capability | Status |
|---|---|
| `processReceipt` (idempotent, validated, duplicate fingerprint) | ✅ emulator-integrated with a fake provider |
| `chefRecommend`, `chefChat`, `scanStorage`, `estimateMeal` | ✅ logic / ⚠️ needs live keys |
| AI router: per-task routing, fallback, schema rejection, usage logging | ✅ |
| Rate limits, AI consent check, App Check enforcement | ✅ (code) / ⚠️ App Check registration |
| `acceptHouseholdInvite`, `deleteAccountData` | ✅ emulator-integrated · `revokeSessions`, `verifyProfessional` 🟡 type-checked only |
| Firestore rules | ✅ emulator-tested |
| Storage rules | ✅ emulator-tested (members only, images only, ≤5 pages, <12 MB, immutable) |
| Indexes, TTL | ✅ declared |

## Not started

- Subscriptions and billing (deferred by design).
- Offline write queue for inventory (decision: v1 tells the user plainly that nothing changed and to retry; reads work offline).
- Spreadsheet export (optional per the directive; JSON export exists).
- Licensed food photography (illustrations are used and labelled as such).
- Push notifications from the server (receipt-ready notices are written in-app; FCM not wired).


## Original directive

The directive was cut off partway through §8 ("11. Confirmed purchase…"). Later sections, if any, were not received; everything above is based on §0–§8.
