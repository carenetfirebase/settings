# Store privacy forms and review notes

These answers describe the production build (`CHEFII_BACKEND=firebase`). They
must match the privacy policy (`web/legal/privacy.html`) and the iOS privacy
manifest (`ios/Runner/PrivacyInfo.xcprivacy`). If a feature changes what is
collected, update all three together.

## Apple App Store: App Privacy ("nutrition label")

**Do you or your third-party partners collect data from this app?** Yes.
**Tracking (ATT)?** No. Chefii does not track users across other companies' apps or websites, has no advertising SDK and never shows the ATT prompt.

| Data type (Apple's wording) | Collected | Linked to user | Used for tracking | Purposes |
|---|---|---|---|---|
| Contact Info › Name | Yes | Yes | No | App Functionality |
| Contact Info › Email Address | Yes | Yes | No | App Functionality |
| Health & Fitness › Health | Yes (glucose journal, food journal, Smile & Food log, concerns notes, dietary needs) | Yes | No | App Functionality |
| Sensitive Info | Yes (dietary restrictions such as halal or kosher-style can reveal religious belief) | Yes | No | App Functionality |
| Purchases › Purchase History | Yes (grocery receipts the user scans) | Yes | No | App Functionality |
| User Content › Photos or Videos | Yes (receipt and fridge photos) | Yes | No | App Functionality |
| User Content › Other User Content | Yes (saved recipes, notes, meal plans, shopping lists) | Yes | No | App Functionality |
| Identifiers › User ID | Yes (account id) | Yes | No | App Functionality |
| Usage Data › Product Interaction | Yes, **only if the user opts in** | No | No | Analytics |
| Diagnostics › Crash Data | Yes | No | No | App Functionality |

Not collected: location, contacts, browsing/search history, financial info (payment cards), audio (voice is transcribed on the device by the operating system's speech service and only the resulting text is used), device ID for advertising, other diagnostics.

Notes for the form:
- Voice input uses the platform speech recognizer (Apple Speech on iOS). Chefii does not record or upload audio.
- Photos are sent to Google's Gemini API only for the single request that reads them, and only after the user turns on AI processing.

## Google Play: Data safety

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes (TLS).
**Do you provide a way for users to request that their data is deleted?** Yes: in-app (You › Export or delete your data › Delete account) and by email to the privacy contact. Deletion URL for the form: the privacy policy section "Deleting your data".

| Category › Type | Collected | Shared* | Optional? | Purposes |
|---|---|---|---|---|
| Personal info › Name | Yes | No | Required | Account management, App functionality |
| Personal info › Email address | Yes | No | Required | Account management |
| Personal info › User IDs | Yes | No | Required | Account management |
| Personal info › Religious or other beliefs | Yes (dietary restrictions) | No | Optional | App functionality |
| Health and fitness › Health info | Yes | No | Optional | App functionality |
| Financial info › Purchase history | Yes (grocery receipts) | No | Optional | App functionality |
| Photos and videos › Photos | Yes | No | Optional | App functionality |
| App activity › App interactions | Yes | No | Optional (opt-in) | Analytics |
| App activity › Other user-generated content | Yes | No | Optional | App functionality |
| App info and performance › Crash logs | Yes | No | Required | App functionality (stability) |

\* Google Play does not count transfers to service providers that process data on Chefii's behalf (Firebase/Google Cloud, Google Gemini API, and OpenAI if enabled) as "sharing". Chefii does not sell data or share it with third parties for their own purposes. Data a user explicitly shares with a professional through the app is user-initiated sharing (also exempt), but mention it in the policy.

Also declare in Play Console:
- **Health apps declaration:** Chefii offers nutrition, glucose journal and oral-health features. It is **not** a medical device and makes no diagnosis or treatment claims.
- **Permissions:** CAMERA (receipt/fridge/barcode scanning), RECORD_AUDIO (voice entry), POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM and USE_FULL_SCREEN_INTENT (the user-configured morning alarm and cooking timers). Exact-alarm use must be justified as an alarm-clock feature; if Play rejects it, switch the morning feature to inexact reminders.
- **Target audience:** 18+ (health records, receipts). Not designed for children.
- **Ads:** No ads.

## Export compliance (Apple)

`ITSAppUsesNonExemptEncryption = false` is set in Info.plist: Chefii only uses encryption provided by the operating system and HTTPS, which is exempt. No annual self-classification report is needed for this.

## Notes for App Review / Play review

Provide a test account (email + password) that you create in the Chefii Firebase project after launch setup, with:
- an example kitchen (the account's onboarding offers "Start with example ingredients"),
- AI processing turned on (You › Privacy & data), so reviewers can try receipt scanning and the AI chef.

Suggested review note:

> Chefii helps people keep track of the food they have at home, suggests recipes, and guides cooking. To try it: sign in with the test account below, open Kitchen to see the example inventory, tap "Scan a receipt" with any grocery receipt photo, then open Today › "Start cooking". Health features (nutrition estimates, glucose journal) are optional, private to the user, show general information with disclaimers, and do not diagnose or treat. Data is stored in Canada. Test account: <email> / <password>.

Apple guideline reminders already handled in the app:
- 4.8 Sign in with Apple is offered alongside Google sign-in.
- 5.1.1(v) In-app account deletion: You › Export or delete your data › Delete account.
- 5.1.1 / 5.1.2 Purpose strings for camera, photos, microphone and speech recognition are in Info.plist.
- 1.4.1 (health): estimates with visible disclaimers; no dosing or diagnostic advice.
