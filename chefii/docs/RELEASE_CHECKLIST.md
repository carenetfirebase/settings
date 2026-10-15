# Release Checklist

## One-time setup

- [ ] Create Firebase projects (dev, prod); choose `northamerica-northeast1` for Firestore and the Storage bucket.
- [ ] `dart pub global activate flutterfire_cli && flutterfire configure` → replaces `lib/firebase_options.dart`.
- [ ] Enable Auth providers: Apple (Services ID, key, return URL), Google (OAuth clients; pass the web client id via `--dart-define=CHEFII_GOOGLE_SERVER_CLIENT_ID`), Email/Password.
- [ ] App Check: register Play Integrity (Android) and App Attest/DeviceCheck (iOS); enforce for Firestore, Storage and Functions.
- [ ] `firebase functions:secrets:set GEMINI_API_KEY` (and `OPENAI_API_KEY` if used).
- [ ] Choose model ids from current provider docs and set `GEMINI_MODEL`, `GEMINI_VISION_MODEL`, `OPENAI_MODEL`, `OPENAI_ENABLED` in `functions/.env.<project>`.
- [ ] `firebase deploy --only firestore:rules,firestore:indexes,storage,functions`.
- [ ] Create an admin user with the `admin: true` custom claim for professional verification.
- [ ] Crashlytics: upload dSYMs (iOS) and set up mapping files (Android).

## Every release

- [ ] CI green: analyze, Flutter tests, functions tests, rules tests, shared-data check.
- [ ] Device integration tests green (iOS and Android, latest and oldest supported).
- [ ] `dart run tool/export_shared_data.dart --check` passes.
- [ ] Receipt evaluation set: no regression against the previous release.
- [ ] Allergen red-team set: 100% recall.
- [ ] Bump the version in `pubspec.yaml`; update release notes.
- [ ] Android: `flutter build appbundle --release --dart-define=CHEFII_BACKEND=firebase`; sign with the upload key; Play Console data safety form matches SECURITY_MODEL.md.
- [ ] iOS: `flutter build ipa --release --dart-define=CHEFII_BACKEND=firebase`; privacy nutrition labels; App Privacy manifest reviewed; usage strings accurate.
- [ ] Web portal: `flutter build web --release --no-web-resources-cdn --dart-define=CHEFII_BACKEND=firebase && firebase deploy --only hosting`.

## Before first public launch

- [ ] Clinical review recorded for every evidence claim (CLINICAL_SAFETY.md).
- [ ] Regulatory opinion: not a medical device in Canada for the shipped feature set.
- [ ] Privacy impact assessment; privacy policy and terms published and linked in-app; DPAs with Google and OpenAI (no training, Canadian or adequate processing).
- [ ] Accessibility audit (VoiceOver, TalkBack, 200% text, contrast).
- [ ] Penetration test of rules and callables.
- [ ] Support inbox monitored (`support@chefii.app` placeholder → real address).
- [ ] Budget alerts on the GCP billing account (OPERATING_COSTS.md).
- [ ] App Store: Apple Sign-In offered alongside Google (Guideline 4.8); in-app account deletion present (screen 80).
