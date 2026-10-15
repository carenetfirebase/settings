# Chefii

*Your kitchen, beautifully taken care of.*

Chefii is a premium kitchen, cooking and nutrition concierge for iOS and Android (Flutter), with a Firebase backend and Gemini (primary) plus optional OpenAI services. It keeps your inventory accurate with almost no typing (receipt scanning, one-tap cooking confirmation, "I used two eggs"), suggests what to cook from what you have, guides you through it, and turns your meals into evidence-based nutrition insights you can share with a dietitian.

## Run it

```bash
flutter pub get
flutter run                      # demo mode: fully offline, labelled sample AI
```

Demo mode needs no accounts or keys. Tap **Continue with a demo account** during onboarding.

With Firebase (after `flutterfire configure`, see `docs/RELEASE_CHECKLIST.md`):

```bash
flutter run --dart-define=CHEFII_BACKEND=firebase
# local emulators:
firebase emulators:start
flutter run --dart-define=CHEFII_BACKEND=firebase --dart-define=CHEFII_EMULATORS=true --dart-define=CHEFII_APPCHECK_DEBUG=true
```

## Test it

```bash
flutter analyze && flutter test                    # 57 tests: domain, flows, full-app widget smoke
(cd functions && npm ci && npm run build && npm test)      # 17 backend tests
(cd rules-tests && npm ci && npm test)            # 13 Firestore rules tests (emulator, needs Java)
dart run tool/export_shared_data.dart --check      # client/server catalogue & allergen parity
```

## Layout

| Path | What |
|---|---|
| `lib/domain` | Pure Dart: units, inventory planner, allergen guard, nutrition, recipes |
| `lib/data` | `DocStore` (Firestore/memory), repositories, auth, AI gateway |
| `lib/app` | Providers, actions, router, app |
| `lib/core/design` | "Quiet Luxury" tokens, theme, components |
| `lib/features` | 80 screens by area |
| `functions/` | Cloud Functions (TypeScript): receipts, chef, scans, accounts |
| `firestore.rules`, `storage.rules` | Security rules (`rules-tests/`) |
| `docs/` | Requirements, architecture, data models, AI contracts, security, clinical safety, plan, tests, status, release, costs, decisions |

**Start with [`docs/FEATURE_STATUS.md`](docs/FEATURE_STATUS.md)** for an honest account of what is done, what is limited, and what needs external setup (Firebase project, AI keys, device builds, clinical review) before launch.

## Licences

Fonts: Cormorant Garamond and Inter, SIL Open Font License 1.1 (`assets/fonts/*-OFL.txt`). Nutrient reference values are rounded from USDA FoodData Central (public domain).
