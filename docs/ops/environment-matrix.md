# PlanDone Environment Matrix

## Goal

Keep Firebase setup reproducible across `dev`, `staging`, and optional `prod` while preserving local-first runtime behavior.

## Environment strategy

| Environment | Purpose | Firebase project alias | Data policy | Deploy policy |
| --- | --- | --- | --- | --- |
| `dev` | Daily local development + emulator-first testing | `dev` (`plandone-dev`) | Disposable/resettable allowed | Fast iteration; rules/index deploys on demand |
| `staging` | Pre-release validation with realistic cloud data | `staging` (`plandone-staging`) | Persistent but non-production | Deploy from tested branch/tag only |
| `prod` (optional) | Live usage | `prod` (`plandone-prod`) | Protected and audited | Manual/approved deploy only |

## Runtime flags contract

`lib/src/core/runtime/runtime_flags.dart` is the source of truth:

- `USE_IN_MEMORY_LOCAL_STORE`
  - `true` for local demo/testing.
  - `false` for Drift-backed persistent local DB.
- `USE_FIREBASE_AUTH`
  - Enables Firebase auth runtime path.
- `USE_FIREBASE_SYNC`
  - Enables Firestore sync adapter + listener hydration.

Recommended per environment:

| Environment | USE_IN_MEMORY_LOCAL_STORE | USE_FIREBASE_AUTH | USE_FIREBASE_SYNC |
| --- | --- | --- | --- |
| `dev` (emulator/local) | `true` or `false` | `false` by default | `false` by default |
| `staging` | `false` | `true` | `true` |
| `prod` | `false` | `true` | `true` |

## Firebase project alias setup

1. Copy `.firebaserc.example` to `.firebaserc`.
2. Replace project ids with your real Firebase project ids.
3. Validate alias resolution:
   - `firebase use dev`
   - `firebase use staging`
   - `firebase use prod` (if used)

## Build/deploy environment selection

Use `FIREBASE_PROJECT` when running npm deploy scripts:

- `FIREBASE_PROJECT=plandone-dev npm run deploy:firestore`
- `FIREBASE_PROJECT=plandone-staging npm run deploy:firestore`
- `FIREBASE_PROJECT=plandone-prod npm run deploy:firestore`
