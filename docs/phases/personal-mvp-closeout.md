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

The build-14 source snapshot was revalidated on September 20, 2026 with:

```bash
flutter analyze
flutter test --concurrency=1
npm run test:rules # under Node 22 and Java 21
```

Results:

- Static analysis reported no issues.
- The Flutter suite passed 264 tests with 11 expected platform skips.
- All 29 Firestore rules tests passed.
- Android release `0.1.0 (15)` was built and distributed through Firebase App
  Distribution to `leveled.dev@gmail.com` on September 20, 2026 as the final
  physical-device QA candidate.
- The complete build-14 source was audited for credential-shaped content,
  committed as `ca9c3b3`, and pushed to `origin/main` on September 20, 2026.

## Remaining manual release gate

The remaining honest gate is a **physical-device manual smoke pass** for the
few interactions not yet directly confirmed on build 15:

- Undo after a move or archive action
- create, edit, move, and archive while offline, followed by online reconciliation
- the complete AI generation, review, reject, and approve path under App Check

Background/closed-app reminders, backup/restore, sign-in, recurrence, and a
basic offline-to-online create/sync path have already passed on the target
Android device.

Use [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md) before calling a build release-ready.

## Supporting docs

- [personal-runtime-profile.md](/home/messay/coding/own/PlanDone/docs/ops/personal-runtime-profile.md)
- [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md)
- [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md)
