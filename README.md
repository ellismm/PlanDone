# PlanDone

PlanDone is an offline-first planning app built with Flutter around a local-first source of truth, optional Firebase auth/sync, and a flexible four-level hierarchy:

- Goal
- Project
- Task
- Action

The product is no longer a Phase 1 starter. It now covers the core daily-use personal MVP workflow:

- route-based workspace, configuration, and planning surfaces
- semantic workflow columns instead of name-coupled done logic
- hierarchy, backlog, focus, and kanban planning views
- quick capture inbox + triage
- saved filter presets
- item activity history
- undo for high-impact actions
- compact/comfortable card density controls
- read-first item details + metadata system
- hierarchy color grouping and parent-path preferences
- deterministic due/start reminders with snooze and mute
- completion-gated recurring tasks with missed-window policies
- deterministic non-AI autofill suggestions
- JSON backup/export and restore-as-new-board

## Current MVP posture

PlanDone is positioned as a **daily-use personal MVP**, not a small-team production platform yet.

### Implemented MVP defaults

- `UI -> State -> Domain -> Repository -> Data Sources` layering remains intact.
- Local Drift storage remains the UI source of truth when persistence is enabled.
- Sync remains `local -> outbox -> Firestore -> hydration -> local`.
- Android reminders use **local scheduled notifications** for due/start alerts, including background/closed-app delivery.
- Recurrence is intentionally **completion-gated only** for the MVP.
- Backup/restore is intentionally **manual JSON export/import** with restore into a new board.
- AI remains deferred.

### Known limitations

See [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md) for the current honest gap list.

## Recommended personal runtime profile

For daily use with persistent local storage and Firebase auth/sync:

```bash
flutter run \
  --dart-define=USE_IN_MEMORY_LOCAL_STORE=false \
  --dart-define=USE_FIREBASE_AUTH=true \
  --dart-define=USE_FIREBASE_SYNC=true
```

Notes:

- Local Android reminders do **not** require `USE_FIREBASE_PUSH=true`.
- `USE_FIREBASE_PUSH=true` is only needed if you want optional FCM device-token registration/manual push testing.
- Full runtime guidance: [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md)

## Validation

Core validation commands:

```bash
npm ci
npm run test:rules
flutter analyze
flutter test
flutter test --concurrency=1
flutter build apk --release
```

Physical Android deploy:

```bash
scripts/deploy_android_latest.sh
```

Android release signing:

- Local debug/deploy builds default to the legacy Android package
  `com.example.plandone` so existing device-local account/workspace data stays
  available during MVP testing.
- For a clean external release id, build with
  `PLANDONE_APPLICATION_ID=com.plandone.app` or Gradle property
  `-PplandoneApplicationId=com.plandone.app`.
- `flutter build apk --release` supports real signing through root-level
  `key.properties` or environment variables:
  `PLANDONE_RELEASE_STORE_FILE`, `PLANDONE_RELEASE_STORE_PASSWORD`,
  `PLANDONE_RELEASE_KEY_ALIAS`, and `PLANDONE_RELEASE_KEY_PASSWORD`.
- If no release signing values are present, local release builds fall back to
  debug signing so validation builds can still complete. Use real signing for
  any build distributed outside local testing.

Manual device regression steps:

- [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md)

## Operations and setup docs

- Environment matrix: [environment-matrix.md](/home/messay/coding/own/PlanDone/docs/ops/environment-matrix.md)
- Android auth setup: [android-auth-setup.md](/home/messay/coding/own/PlanDone/docs/ops/android-auth-setup.md)
- Backend runbook: [runbook.md](/home/messay/coding/own/PlanDone/docs/ops/runbook.md)
- Optional FCM extension path: [push-notifications-phone-setup.md](/home/messay/coding/own/PlanDone/docs/ops/push-notifications-phone-setup.md)
- Personal MVP closeout summary: [personal-mvp-closeout.md](/home/messay/coding/own/PlanDone/docs/phases/personal-mvp-closeout.md)

## Phase docs

Roadmap and phase-by-phase docs live in [`docs/phases/`](/home/messay/coding/own/PlanDone/docs/phases) with prompt companions in [`docs/prompts/`](/home/messay/coding/own/PlanDone/docs/prompts).

Recommended starting points:

- [roadmap.md](/home/messay/coding/own/PlanDone/docs/phases/roadmap.md)
- [progress-checklist.md](/home/messay/coding/own/PlanDone/docs/phases/progress-checklist.md)
- [personal-mvp-closeout.md](/home/messay/coding/own/PlanDone/docs/phases/personal-mvp-closeout.md)

## Deferred intentionally

These are not blockers for the current personal MVP:

- AI/LLM-assisted breakdown and generation
- automated backend-driven push reminder pipeline
- complex calendar/RRULE recurrence semantics
- merge-based import tooling
- broader multi-user onboarding/release operations polish
