#!/usr/bin/env bash
# One-time setup of a NEW Chefii Firebase project, run on your own computer
# from the chefii/ folder:
#
#   bash tool/setup_firebase.sh chefii-xxxxx
#
# It connects the app to the project, stores the Gemini API key in Secret
# Manager (typed at a hidden prompt, never saved in the repo), records the
# model ids, and deploys rules, functions and the website. It refuses any
# project that is not named chefii / chefii-* (see tool/guard_firebase_project.sh).
set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" ]]; then
  echo "Usage: bash tool/setup_firebase.sh <chefii-project-id>" >&2
  exit 1
fi
bash tool/guard_firebase_project.sh "$PROJECT"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Checking tools"
command -v flutter >/dev/null || { echo "Install Flutter first: https://docs.flutter.dev/get-started/install" >&2; exit 1; }
command -v node >/dev/null || { echo "Install Node.js 22 first: https://nodejs.org" >&2; exit 1; }
command -v firebase >/dev/null || npm install -g firebase-tools
dart pub global activate flutterfire_cli >/dev/null
export PATH="$PATH:$HOME/.pub-cache/bin"

step "Signing in to Firebase (a browser window may open)"
firebase login

step "Connecting the app to $PROJECT"
flutterfire configure \
  --project="$PROJECT" \
  --platforms=ios,android,web \
  --ios-bundle-id=ca.chefii.chefii \
  --android-package-name=ca.chefii.chefii \
  --out=lib/firebase_options.dart \
  --yes
printf '{\n  "projects": {\n    "default": "%s"\n  }\n}\n' "$PROJECT" > .firebaserc

step "AI model ids"
echo "Open https://aistudio.google.com and copy the id of a current Gemini model"
echo "(a fast 'Flash' model is a good default for both)."
read -r -p "Gemini model id for chef, chat and meals: " GEMINI_MODEL
read -r -p "Gemini model id for receipts and photos [same]: " GEMINI_VISION_MODEL
GEMINI_VISION_MODEL="${GEMINI_VISION_MODEL:-$GEMINI_MODEL}"
cat > "functions/.env.$PROJECT" <<EOF
GEMINI_MODEL=$GEMINI_MODEL
GEMINI_VISION_MODEL=$GEMINI_VISION_MODEL
OPENAI_MODEL=unused
OPENAI_ENABLED=false
EOF

step "Gemini API key (paste it at the hidden prompt; it is stored in Google Secret Manager)"
firebase functions:secrets:set GEMINI_API_KEY --project "$PROJECT"
echo "OpenAI is optional and off. To skip it, enter any placeholder at the next prompt."
firebase functions:secrets:set OPENAI_API_KEY --project "$PROJECT"

step "Building the website (privacy policy, terms, professional portal)"
flutter pub get
flutter build web --release --no-web-resources-cdn --dart-define=CHEFII_BACKEND=firebase

step "Deploying to $PROJECT"
(cd functions && npm ci)
firebase deploy --project "$PROJECT" --only firestore,storage,functions,hosting

step "Done"
echo "Website: https://$PROJECT.web.app  (legal pages under /legal/)"
echo "Next: commit lib/firebase_options.dart, .firebaserc and the new"
echo "android/app/google-services.json and ios/Runner/GoogleService-Info.plist"
echo "(they identify the project; they are not secrets). See docs/LAUNCH_STEPS.md."
