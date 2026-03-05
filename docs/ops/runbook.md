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

## Incident playbooks

### 1) Outbox not draining

1. Confirm runtime flags:
   - `USE_FIREBASE_SYNC=true`
   - `USE_IN_MEMORY_LOCAL_STORE=false` (for persistent local state)
2. Open pending outbox UI and inspect failures.
3. Trigger `Sync now`.
4. Verify Firestore access/rules for the active user role.
5. Check emulator/cloud logs for permission or payload errors.

### 2) Permission denied spike

1. Run `npm run test:rules`.
2. Diff `firestore.rules` against last known good revision.
3. Confirm member role/`joinedAtEpochMillis` status in Firestore docs.
4. If regression confirmed:
   - roll forward with fixed rules, or
   - roll back rules to previous known-good version.

### 3) Rules/index deploy regression

1. Deploy to `staging` first:
   - `FIREBASE_PROJECT=<staging-project> npm run deploy:firestore`
2. Run app smoke tests on staging data.
3. Promote to prod only after passing checks.
4. Record deploy SHA + timestamp.

### 4) Emulator instability

1. Stop emulator process.
2. Backup/remove `.firebase/emulator-data` if corrupted.
3. Restart with `npm run emulators:firestore`.
4. Re-run `npm run test:rules`.

## Decision path: Firebase-only vs extension path

### Firebase-only (default now)

Choose this when:

- current app behavior is fully covered by client + rules + sync adapter
- operational overhead should stay minimal
- team size is small and velocity matters most

### Firebase + Cloud Functions/Run extension

Choose this when you need:

- trusted server-only workflows (privileged automation, scheduled jobs)
- cross-board aggregation/reporting beyond client practical limits
- stronger centralized audit/guardrail logic

If extension path is selected, keep the current Firebase discipline:

- rules remain mandatory
- local-first write flow remains primary
- server paths are additive, not replacements for client safety checks
