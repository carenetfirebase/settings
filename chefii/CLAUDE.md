# Rules for this repository

## Never touch Referai (highest priority)

Referai is the owner's primary production app. It lives in the same Google /
Firebase account as Chefii. **Nothing done from this repository may read,
modify, deploy to, rename, delete or reconfigure Referai** in any way:

- Never run `firebase`, `gcloud`, `flutterfire` or any other command against the
  Referai Firebase / Google Cloud project, its apps, rules, functions, hosting,
  Storage, Auth, secrets or billing.
- Never rename, reuse or "convert" the Referai project for Chefii. Chefii uses
  its own separate project (`chefii` / `chefii-*`).
- Never copy Referai's config files, API keys, `google-services.json`,
  `GoogleService-Info.plist` or `firebase_options.dart` into this repository.
- If a task seems to need anything from Referai, stop and ask the owner first.

Enforced by `tool/guard_firebase_project.sh` (runs before every
Firebase deploy and blocks any project that is not `chefii*`) and by a Claude
Code hook in the repository root `.claude/settings.json`.

