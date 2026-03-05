# Phase 7 — Cloud Backend Infrastructure Baseline

## Why this phase exists

PlanDone already uses Firebase services, but a daily-use-ready product needs stronger cloud organization, environment separation, and operational reliability even if immediate public deployment is not planned.

## Scope

### In scope

- Define environment strategy (`dev`, `staging`, optional `prod`) and promotion path.
- Standardize Firebase project/app configuration and runtime flags per environment.
- Harden backend operations baseline:
  - rules/index deployment discipline
  - reproducible emulator + CI checks
  - operational logging for sync/auth issues
- Document incident basics (stuck sync, permission spikes, rules regression).
- Evaluate optional server-side extension path:
  - Firebase-only baseline, or
  - Firebase + Cloud Functions/Run for constrained workflows.

### Out of scope

- Full SRE platform build-out.
- AI/automation features (Phase 9).

## Key implementation targets

1. Create environment matrix and required configs/secrets per environment.
2. Add CI path for rules tests + Flutter tests + basic lint/build checks.
3. Ensure reproducible local emulation and cloud deployment steps.
4. Define cloud responsibilities requiring user/admin setup actions.
5. Document backend governance for project/team continuity.

## User actions likely required

- Confirm Firebase project strategy (single vs multi-project).
- Enable billing and set preferred region(s).
- Provide service-account/runtime secret management approach.
- Decide whether to keep Firebase-only or include Cloud Functions/Run now.

## Risks and mitigations

- **Risk:** environment drift causes inconsistent behavior.  
  **Mitigation:** explicit environment contracts + CI enforcement.
- **Risk:** weak observability slows issue diagnosis.  
  **Mitigation:** baseline telemetry and troubleshooting runbooks.

## Acceptance criteria

- Environment setup is documented and reproducible.
- Rules/tests/deployment process is consistent and automatable.
- Team can run local emulator flows and cloud validation reliably.
- Cloud decisions and ownership boundaries are explicit.

## Exit artifacts

- Cloud baseline architecture note.
- Environment setup + promotion runbook.
- Phase-7 checklist completion summary.

---

## Phase-7 implementation summary (current status)

### 1) Brief implementation plan

1. Define explicit `dev/staging/prod` environment contracts.
2. Standardize Firebase rules/index/emulator/deploy scripts.
3. Add CI baseline for rules tests + Flutter analyze/test.
4. Publish ops runbook with incident playbooks.
5. Separate user/cloud-admin actions from code changes.

### 2) Environment matrix and setup summary

- Added environment strategy matrix and runtime flag guidance:
  - `docs/ops/environment-matrix.md`
- Added Firebase alias template:
  - `.firebaserc.example`
- Runtime flags remain the source of truth in:
  - `lib/src/core/runtime/runtime_flags.dart`

### 3) Code/config/docs changes

- `package.json`
  - added `emulators:firestore`
  - added `deploy:rules`
  - added `deploy:indexes`
  - added `deploy:firestore`
- `.github/workflows/ci.yml`
  - Node setup + `npm run test:rules`
  - Flutter setup + `flutter analyze --no-fatal-infos --no-fatal-warnings` + `flutter test`
- `docs/ops/runbook.md`
  - command baseline
  - incident playbooks
  - Firebase-only vs extension decision path
- `.gitignore`
  - ignores `.firebase/` emulator export data

### 4) User/cloud-admin must-do checklist

1. Create/confirm Firebase projects for `dev`, `staging`, optional `prod`.
2. Copy `.firebaserc.example` to `.firebaserc` and set real project ids.
3. Enable Firestore + Authentication providers in each project.
4. Ensure IAM access for deploy operator account.
5. Set billing/region policies for staging/prod projects as needed.
6. Run staged deploy flow:
   - `FIREBASE_PROJECT=<dev> npm run deploy:firestore`
   - `FIREBASE_PROJECT=<staging> npm run deploy:firestore`
   - optional prod promotion after validation.

### 5) Phase-7 acceptance checklist results

- [x] Environment setup is documented and reproducible.
- [x] Rules/tests/deploy process is consistent and automatable.
- [x] Required user/cloud-admin actions are explicit.
- [x] Docs are coherent with current repository setup.
