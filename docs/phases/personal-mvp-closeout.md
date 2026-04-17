# Personal MVP Closeout

## Goal

Close the remaining trust-and-reliability gaps for PlanDone as a **daily-use personal MVP** without redesigning the core architecture.

## Implemented in this closeout

### 1. Real reminder delivery

- Added a notification delivery adapter in Flutter.
- Added Android local scheduled reminder delivery via `AlarmManager`.
- Added Android notification channel, permission request flow, boot/package-replace rescheduling, and schedule replacement from canonical local reminder state.
- Kept the baseline MVP path local-first and offline-safe.

### 2. Release-readiness hardening

- Full `flutter test` suite is green.
- `npm run test:rules` is green.
- Added explicit personal smoke checklist and recommended runtime profile docs.
- Added known limitations doc to keep release status honest.

### 3. Recurrence completion

- Preserved deterministic completion-gated recurrence as the MVP default.
- Added missed-window policy support:
  - `nextEligible`
  - `singleStep`
  - `manualCatchUp`
- Preserved duplicate suppression and validation safety.

### 4. Backup/export safety

- Added JSON export of full board snapshots.
- Added restore/import as a new board.
- Preserved columns, hierarchy, metadata, recurrence, and workflow semantics during restore.

### 5. Docs/product-truth cleanup

- Rewrote `README.md` to reflect the current product, not a Phase 1 starter.
- Updated notification and recurrence phase docs to match actual implementation.
- Added operational docs for personal runtime, smoke validation, and known limitations.

## Validation summary

Validated on March 18, 2026 with:

```bash
npm run test:rules
flutter test
```

Results:

- Firestore rules tests passed.
- Flutter test suite passed.

## Remaining manual release gate

The remaining honest gate is a **physical-device manual smoke pass**, especially for:

- background/closed-app reminder delivery
- offline -> online recovery
- backup/restore confidence on target device

Use [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md) before calling a build release-ready.

## Supporting docs

- [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md)
- [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md)
- [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md)
