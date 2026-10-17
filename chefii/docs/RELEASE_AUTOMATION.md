# Release automation (optional, saves using Xcode)

`.github/workflows/chefii-release.yml` builds signed releases and uploads
them for testing: **Android → Google Play internal testing** and
**iOS → TestFlight**. Run it from GitHub › **Actions** › **Chefii release** ›
**Run workflow**, entering a build number that's higher than the last upload
(2, 3, 4…).

It refuses to run until the app is connected to a Chefii Firebase project
(`tool/setup_firebase.sh`). Each platform is skipped until its secrets
exist.

Add secrets at GitHub › repository **Settings** › **Secrets and variables** ›
**Actions** › **New repository secret**. Never paste them into chat or
commit them.

## Android

| Secret | What it is / how to get it |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Your upload keystore (LAUNCH_STEPS step 5) encoded as text: `base64 -i ~/chefii-upload.jks \| pbcopy` on a Mac, then paste |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password you chose |
| `ANDROID_KEY_PASSWORD` | The key password you chose (often the same) |
| `ANDROID_KEY_ALIAS` | `upload` (if you used the command in LAUNCH_STEPS) |
| `PLAY_SERVICE_ACCOUNT_JSON` *(optional, for auto-upload)* | Play Console › Setup › API access › create a service account in Google Cloud (in the **Chefii** project), grant it "Release to testing tracks" in Play Console, create a JSON key, paste the whole file |

Google Play needs the **first** upload done by hand in Play Console (step 5 of
LAUNCH_STEPS). After that, this workflow uploads drafts to internal testing.

## iOS

| Secret | What it is / how to get it |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com › Membership details › Team ID (10 characters) |
| `ASC_KEY_ID` | App Store Connect › Users and Access › **Integrations** › App Store Connect API › generate a key with **App Manager** access; its Key ID |
| `ASC_ISSUER_ID` | Shown on the same page, above the keys |
| `ASC_KEY_P8_BASE64` | The downloaded `AuthKey_XXXX.p8`, encoded: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |

The app record must exist in App Store Connect (LAUNCH_STEPS step 4.4).
Signing certificates and profiles are created automatically by Xcode on the
build machine using the API key.

## Not yet tested

This workflow has been written and syntax-checked, but it can't run until
your accounts and secrets exist. Expect the first run to need a small fix;
send me the failing job's log and I'll fix it.
