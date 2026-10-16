# Security & Privacy Model

## Data classes

| Class | Examples | Location | Who can read |
|---|---|---|---|
| Household kitchen | lots, ledger, receipts, plan, shopping, saved recipes | `households/{hid}/**` | household members |
| Personal (sensitive) | dietary profile, journal, glucose, oral log, concerns, consents, audit | `users/{uid}/**` | the user; a verified professional **read-only** while an explicit grant covers that category and time range |
| Shared safety | allergens a member opts to share | `households/{hid}/members/{uid}.sharedAllergens` | household members |
| Professional | profile, verification status | `professionals/{uid}` | signed-in users (status writable only by server) |
| Operational | AI usage metadata, rate limits | `aiUsage`, `rateLimits` | server only |
| Receipt images | photos | Storage `households/{hid}/receipts/{rid}/page_n` | household members |

## Controls

- **Authentication:** Firebase Auth (Apple, Google, email). Sensitive actions (export, account deletion, session revocation) reauthenticate; `deleteAccountData` additionally requires `auth_time` within 5 minutes.
- **Authorisation:** `firestore.rules` and `storage.rules` (deny by default). Covered by Firestore and Storage emulator tests in `rules-tests/` and callable integration tests (`functions/src/callables.int.test.ts`) — membership, append-only ledger, one-time undo marker, no negative stock, no lot deletion, owner-only membership removal, private health data invisible to household members, no self-granted professional status, server-only collections, grant id/verification requirements, category + time-range scoping, immediate effect of revocation/expiry, client-only response to assessments, access logs.
- **App Check:** enforced on all callables (Play Integrity / App Attest with DeviceCheck fallback; debug provider via `CHEFII_APPCHECK_DEBUG`).
- **Secrets:** AI keys in Secret Manager, bound only to functions that need them. No secrets in the app bundle or repo (`.env.example` only).
- **Input validation:** client sniffs image magic bytes and limits size/pages; server re-checks paths, content type, size; all callable inputs are type/length-checked; model output schema-validated.
- **AI consent:** server refuses AI processing without `aiProcessingConsent`; the app asks inline before first use; consent history is append-only.
- **Least data to AI:** chef prompts include inventory and dietary constraints only — no names, emails, journal or health records. Receipt/fridge images are sent only for that request. OpenAI calls use `store: false`.
- **Rate limits:** per-user daily quotas per AI task (transactional counter with TTL).
- **Audit:** share grants/revocations and exports write to the user's append-only audit log; professional views write to the grant's access log, visible to the client.
- **Analytics:** opt-in only; parameters filtered against an allow-list of enum-like tokens and numbers (`sanitizeAnalyticsParams`) — no food names, free text or health data.
- **Crash reporting:** Crashlytics stack traces only; no user content attached.
- **Device storage:** Android cloud backup and device-transfer disabled for app data (`data_extraction_rules.xml`, `allowBackup=false`). Demo mode stores data only on device.
- **Web portal headers:** HSTS, `nosniff`, `DENY` framing, strict referrer policy (`firebase.json`). CanvasKit can be self-hosted (`--no-web-resources-cdn`) to avoid third-party fetches.

## Residency and compliance

Firestore, Functions and (configured) Storage in `northamerica-northeast1` (Montréal). Designed toward PIPEDA principles (consent, purpose limitation, access via export, deletion) and provincial health-information laws (e.g. Ontario PHIPA, Alberta HIA) where a health custodian is involved. **A privacy impact assessment and legal review are required before launch** — see RELEASE_CHECKLIST.md. Data-processing agreements with Google and OpenAI must confirm no training on customer data.

## Known gaps (tracked in FEATURE_STATUS)

- No field-level encryption of glucose/journal beyond Google Cloud encryption at rest.
- Professional verification is a manual admin process (`verifyProfessional`), with no automated registry lookup.
- No penetration test yet.
