# Implementation Plan

## Done (this branch)

1. **Foundations:** Flutter 3.47 project (iOS, Android, web), bundled OFL fonts, design tokens, theme and component library.
2. **Domain:** units, models, consumption planner, allergen guard, nutrition calculator, matcher, command parser, curated recipes, substitutions, evidence library.
3. **Data:** `DocStore` abstraction (Firestore and memory), repositories, idempotent inventory ledger, receipt import service, cooking, planning, journal, health, sharing, export.
4. **App:** providers, actions, router with guards, all 80 screens, notifications, voice, privacy-safe analytics, consent prompts.
5. **Backend:** callables, AI router and providers, schemas, deterministic validation, rules, indexes, emulator rules tests.
6. **Platform:** Android and iOS permissions, deep links, backup exclusion, minimum OS versions.

## Next milestones

### M1 — Connect real infrastructure (1–2 weeks)
- Create Firebase projects (`chefii-dev`, `chefii-prod`) in `northamerica-northeast1`; run `flutterfire configure`; register App Check providers.
- Set secrets and model params; deploy rules, indexes and functions to dev.
- Build on devices; fix native issues (document scanner, notifications, speech).
- Wire the receipt evaluation set; tune prompts; choose models by accuracy and cost.

### M2 — Hardening (2–3 weeks)
- Emulator integration tests for callables; Storage rules tests; device integration tests.
- Offline write queue for inventory (operation records already make replay safe).
- FCM push for "receipt ready" and sharing invitations.
- Wakelock during guided cooking; notification action buttons (snooze, done).
- Custom storage locations; product photos.

### M3 — Clinical, legal and accessibility sign-off (parallel)
- Dietitian and dental review of the evidence library and copy; record sign-off.
- Privacy impact assessment; terms and privacy policy; data-processing agreements with AI providers.
- TalkBack/VoiceOver audit; dark theme QA; French localisation (ARB files and translated evidence).

### M4 — Beta
- TestFlight and Play internal testing with about 50 Canadian households.
- Track the success measures in PRODUCT_REQUIREMENTS.md.
- Professional pilot with 3–5 registered dietitians.

### M5 — Monetisation (after core is stable)
- Store subscriptions (StoreKit 2 / Play Billing via a maintained plugin), entitlements in Firestore written by verified server-side receipt validation.

## Later
- HealthKit / Health Connect read-only glucose import with provenance.
- iOS AlarmKit bridge for true system alarms.
- External barcode database (e.g. Open Food Facts) with allergen data.
- Licensed editorial photography library keyed by recipe.
