# Your launch steps

Everything that can be built, tested and written without your accounts is
done. These steps need you (your logins, payments, devices and legal
decisions). Do them in order; most take 10–30 minutes. Steps marked 🧑‍⚖️ need
a professional.

> **Referai is never touched.** Every step below creates or uses a **new,
> separate** Chefii project. The deploy guard refuses any Firebase project
> whose id doesn't start with `chefii`.

## 1. Create the Chefii Firebase project (15 min)

1. Go to <https://console.firebase.google.com> with your usual Google account → **Add project**.
2. Name it **Chefii**. Firebase suggests an id like `chefii-a1b2c`. It must start with `chefii`. Write it down.
3. Google Analytics: on (it stays off in the app until each user opts in).
4. Upgrade to the **Blaze** (pay-as-you-go) plan. Cloud Functions require it. Then in Google Cloud Billing set a **budget alert** (e.g. $50/month); see `docs/OPERATING_COSTS.md`.
5. **Firestore Database** → Create → location **northamerica-northeast1 (Montréal)** → production mode.
6. **Storage** → Get started → same location.
7. **Authentication** → Sign-in method → enable **Email/Password** and **Google**. (Apple comes in step 4.)

## 2. Gemini API key (5 min)

1. Open <https://aistudio.google.com> → **Get API key** → **Create API key** → choose the **Chefii** Google Cloud project (not Referai).
2. Copy the key. Don't paste it into chat or email: the setup script asks for it at a hidden prompt.

## 3. Connect and deploy (20 min, on your Mac)

You need Flutter, Node.js 22 and Xcode installed. In Terminal:

```bash
git clone https://github.com/carenetfirebase/settings.git
cd settings && git checkout claude/chefii-flutter-app && cd chefii
bash tool/setup_firebase.sh chefii-a1b2c      # your project id
```

The script signs you in and connects the app, asks for the model ids and the Gemini key, and deploys everything. When it finishes, commit the files it lists and push, or tell me and I'll take it from there.

## 4. Apple (App Store) (≈1 hour; developer account needed)

1. <https://developer.apple.com> → Identifiers → register App ID **ca.chefii.chefii** with **Sign in with Apple** enabled. ⚠️ This id is permanent after the first release; if you'd prefer your company's reverse domain, tell me before this step.
2. Sign in with Apple for Firebase: create a **Services ID** and a **key**, then paste them into Firebase → Authentication → Apple (Firebase shows exactly which fields).
3. App Check: Firebase → App Check → register the iOS app with **App Attest**.
4. App Store Connect → **New App**: name "Chefii: Kitchen & Recipes", primary language English (Canada), add French (Canada), bundle id ca.chefii.chefii, SKU `chefii-ios`.
5. Build: open `ios/Runner.xcworkspace` in Xcode → Signing: choose your team → Product › **Archive** → Distribute → App Store Connect. (Or ask me to set up automatic signing in CI.)
6. Paste the listing from `docs/store/LISTING.md`, upload screenshots from `store/screenshots/ios/`, answer App Privacy from `docs/store/APP_PRIVACY.md`, add the privacy policy URL `https://<project>.web.app/legal/privacy.html`.
7. Send to **TestFlight** first and install it on your iPhone.

## 5. Google Play (≈1 hour; developer account needed)

1. Create the **upload key** (once; keep it backed up):
   ```bash
   keytool -genkey -v -keystore ~/chefii-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Then create `android/key.properties` (never committed):
   ```
   storePassword=…
   keyPassword=…
   keyAlias=upload
   storeFile=/Users/<you>/chefii-upload.jks
   ```
2. Build: `flutter build appbundle --release --dart-define=CHEFII_BACKEND=firebase`.
3. Play Console → **Create app** "Chefii: Kitchen & Recipes", default language English (Canada), add French (Canada). Upload `build/app/outputs/bundle/release/app-release.aab` to **Internal testing**.
4. Firebase → App Check → register Android with **Play Integrity**; add the Play app-signing SHA-256 to the Firebase Android app (Project settings).
5. Store listing from `docs/store/LISTING.md`, graphics from `store/` (icon, feature graphic, screenshots), Data safety from `docs/store/APP_PRIVACY.md`, health-apps declaration, target audience 18+.

## 6. Legal and professional reviews (in parallel)

- 🧑‍⚖️ **Privacy policy and terms:** fill the [BRACKETED] items in `web/legal/*.html` (legal name, address, privacy officer, contact email). Have a Canadian lawyer review them, including for Québec Law 25 and consumer law. Remove the draft notice, then redeploy (`firebase deploy --only hosting`).
- 🧑‍⚕️ **Dietitian (and dentist for Smile & Food):** review the evidence notes and food data (`docs/CLINICAL_SAFETY.md`).
- 🇫🇷 **Bilingual reviewer from Québec:** go through `docs/FRENCH_REVIEW.md`.
- **Support email:** replace `support@chefii.app` in the app and pages with a real inbox you monitor.

## 7. Test on real phones (1–2 hours)

On TestFlight and Play internal testing, in English and French:
- Scan a real grocery receipt (English and French receipt), confirm items.
- Ask the chef for dinner ideas; cook one recipe with timers; check the screen stays on.
- Voice: "I used two eggs" / « J'ai utilisé deux œufs ».
- Morning alarm and a meal reminder, including **Snooze 10 min**.
- Turn on VoiceOver/TalkBack for a few screens.
- Create the **App Review test account** (email/password) with the example kitchen and AI turned on; put it in the review notes (`docs/store/APP_PRIVACY.md`).

Tell me what you find. I'll fix issues, and the CI builds will confirm both apps.

## 8. Submit

When TestFlight and internal testing look good and the reviews are done: submit for review in App Store Connect and promote to Production in Play Console.
