# PlanDone Backend Ops Runbook

## Baseline commands

### Rules tests

```bash
npm ci
npm run test:rules
```

### Flutter validation

```bash
flutter pub get
flutter analyze
flutter test
```

### Emulator workflow

```bash
npm run emulators:firestore
```

Uses import/export persistence at `.firebase/emulator-data`.

### Firestore rules/index deploys

```bash
FIREBASE_PROJECT=plandone-dev npm run deploy:rules
FIREBASE_PROJECT=plandone-dev npm run deploy:indexes
FIREBASE_PROJECT=plandone-dev npm run deploy:firestore
```

Promote the same workflow from `dev` -> `staging` -> `prod`.

## Personal MVP release routine

1. Run `npm run test:rules`.
2. Run `flutter test`.
3. Deploy the latest Android build.
4. Execute [personal-mvp-smoke-checklist.md](/home/messay/coding/own/PlanDone/docs/ops/personal-mvp-smoke-checklist.md).
5. Record any residual issues in [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md).

## Incident playbooks

### 1. Outbox not draining

1. Confirm runtime flags:
   - `USE_FIREBASE_SYNC=true`
   - `USE_IN_MEMORY_LOCAL_STORE=false`
2. Open pending outbox UI and inspect failures.
3. Trigger `Sync now`.
4. Verify Firestore access/rules for the active user role.
5. Check emulator/cloud logs for permission or payload errors.

### 2. Permission denied spike

1. Run `npm run test:rules`.
2. Diff `firestore.rules` against the last known good revision.
3. Confirm member role and `joinedAtEpochMillis` status in Firestore docs.
4. If regression is confirmed:
   - roll forward with fixed rules, or
   - roll back rules to the previous known-good version.

### 3. Rules/index deploy regression

1. Deploy to `staging` first:
   - `FIREBASE_PROJECT=<staging-project> npm run deploy:firestore`
2. Run app smoke tests on staging data.
3. Promote to prod only after passing checks.
4. Record deploy SHA and timestamp.

### 4. Emulator instability

1. Stop emulator process.
2. Backup/remove `.firebase/emulator-data` if corrupted.
3. Restart with `npm run emulators:firestore`.
4. Re-run `npm run test:rules`.

### 5. Local reminders not firing on Android

1. Confirm the item has `startAt` or `dueAt` metadata and reminders are enabled.
2. Verify reminder settings are not muted or snoozed.
3. Confirm Android notification permission is granted.
4. Reopen the app once to force reminder schedule reconciliation.
5. If the device has aggressive battery optimization, exempt the app and retry.

### 6. Backup restore failure

1. Open `Board Configuration -> Backup & Restore` and confirm the file appears in the list.
2. If a backup file is malformed, delete it from the backup list and export a fresh snapshot.
3. Remember restore imports as a new board; it does not merge into the current board.
4. If the restored board is missing expected collaboration data, check [known-limitations.md](/home/messay/coding/own/PlanDone/docs/phases/known-limitations.md).

## Decision path: Firebase-only vs extension path

### Firebase-only (default MVP path)

Choose this when:

- current app behavior is fully covered by client + rules + sync adapter
- operational overhead should stay minimal
- local scheduled Android reminders are sufficient
- team size is small and velocity matters most

### Firebase + Cloud Functions/Run extension

Choose this when you need:

- trusted server-only workflows (privileged automation, scheduled jobs)
- automated push reminder delivery beyond local device scheduling
- cross-board aggregation/reporting beyond client practical limits
- stronger centralized audit/guardrail logic

If the extension path is selected, keep the current Firebase discipline:

- rules remain mandatory
- local-first write flow remains primary
- server paths are additive, not replacements for client safety checks
