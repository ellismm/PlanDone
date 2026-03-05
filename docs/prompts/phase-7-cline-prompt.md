# Cline Prompt — Phase 7 (Cloud Backend Infrastructure Baseline)

Implement **Phase 7** for PlanDone, aligned to the revised roadmap.

## Objective

Harden cloud/backend operations for reliable daily use, with clear environment strategy and reproducible setup, while preserving the existing Firebase-centered architecture.

## Non-negotiables

1. Keep local-first/offline-first runtime behavior.
2. Do not bypass Firestore rules discipline.
3. Keep setup reproducible for dev/staging/(optional)prod.
4. Clearly separate code changes from required user/cloud-admin setup actions.

## Scope to implement now

1. Define and document environment strategy (dev/staging/(optional)prod).
2. Standardize Firebase config/runtime flags per environment.
3. Improve backend ops baseline:
   - rules/index deployment workflow
   - emulator reliability workflow
   - CI checks (rules tests + Flutter tests + lint/build basics)
4. Add/update operational runbook for common incidents.
5. Document decision path:
   - Firebase-only
   - Firebase + Cloud Functions/Run extension

## Constraints

- No broad backend platform migration.
- Keep secrets and credentials handling explicit and secure.
- Keep docs actionable for one-person and small-team usage.

## Required output from you

1. Brief implementation plan.
2. Environment matrix and setup summary.
3. Code/config/docs changes.
4. Clear “user must do” checklist for cloud-console steps.
5. Phase-7 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Environment setup is documented and reproducible.
- Rules/tests/deploy process is consistent and automatable.
- Required user/cloud-admin actions are explicit.
- Docs are coherent with current repository setup.

## Validation commands

- `npm run test:rules`
- `flutter test`
- (optional) emulator start/deploy dry-run commands
