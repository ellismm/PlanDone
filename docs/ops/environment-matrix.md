# PlanDone Environment Matrix

## Goal

Keep Firebase setup reproducible across `dev`, `staging`, and optional `prod` while preserving local-first runtime behavior.

## Environment strategy

| Environment | Purpose | Firebase project alias | Data policy | Deploy policy |
| --- | --- | --- | --- | --- |
| `dev` | Daily local development + emulator-first testing | `dev` (`plandone-dev`) | Disposable/resettable allowed | Fast iteration; rules/index deploys on demand |
| `staging` | Pre-release validation with realistic cloud data | `staging` (`plandone-staging`) | Persistent but non-production | Deploy from tested branch/tag only |
| `prod` (optional) | Live usage | `prod` (`plandone-prod`) | Protected and audited | Manual/approved deploy only |

## Runtime profile contract

`lib/src/core/runtime/runtime_flags.dart` is the source of truth:

- `PLANDONE_RUNTIME_PROFILE`
  - `local` selects device-only authentication and no cloud sync.
  - `firebase` selects real Firebase Auth and Firestore sync.

- `USE_IN_MEMORY_LOCAL_STORE`
  - `true` for local demo/testing.
  - `false` for Drift-backed persistent local DB.
- `USE_FIREBASE_AUTH`
  - Enables Firebase auth runtime path.
- `USE_FIREBASE_SYNC`
  - Enables Firestore sync adapter + listener hydration.
- `USE_FIREBASE_PUSH`
  - Enables optional FCM token registration/manual push path.
- `USE_FIREBASE_AI`
  - Enables the Phase 9 Firebase AI Logic provider after App Check activation.
- `PLANDONE_FIREBASE_AI_MODEL`
  - Selects the Firebase AI Logic model without changing domain contracts.
- `PLANDONE_FIREBASE_AI_FALLBACK_MODEL`
  - Selects the one-time free fallback used only when the primary model returns
    a quota-exceeded response.

Checked-in profile files:

- `config/runtime/local.json`
- `config/runtime/firebase.json`

Recommended per environment:

| Environment | Runtime file | Auth/sync behavior |
| --- | --- | --- |
| `dev` (device-local) | `config/runtime/local.json` | Persistent local data; no Firebase |
| `dev`/`staging` (connected) | `config/runtime/firebase.json` | Firebase Auth + Firestore sync |
| `prod` | `config/runtime/firebase.json` | Firebase Auth + Firestore sync; real signing required |

## Recommended personal-use profile

For day-to-day personal use on Android, use
`config/runtime/firebase.json`. Add `USE_FIREBASE_PUSH=true` only while testing
the optional FCM extension path. AI is enabled in this profile for the protected
`plandone-staging` Firebase AI Logic service; keep it disabled in local-only
profiles. See [firebase-ai-setup.md](/home/messay/coding/own/PlanDone/docs/ops/firebase-ai-setup.md).

See [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md).
For Android auth wiring and biometric quick unlock setup, see [android-auth-setup.md](/home/messay/coding/own/PlanDone/docs/ops/android-auth-setup.md).

## Firebase project alias setup

1. Copy `.firebaserc.example` to `.firebaserc`.
2. Replace project ids with your real Firebase project ids.
3. Validate alias resolution:
   - `firebase use dev`
   - `firebase use staging`
   - `firebase use prod` if used

## Build/deploy environment selection

Build Android APKs through the profile-aware wrapper:

- `scripts/build_android_profile.sh local debug`
- `scripts/build_android_profile.sh firebase release`

Firebase builds require `android/app/google-services.json`. Distribution builds
should also set `PLANDONE_REQUIRE_RELEASE_SIGNING=true`.

Use `FIREBASE_PROJECT` independently when deploying backend resources:

- `FIREBASE_PROJECT=plandone-dev npm run deploy:firestore`
- `FIREBASE_PROJECT=plandone-staging npm run deploy:firestore`
- `FIREBASE_PROJECT=plandone-prod npm run deploy:firestore`
