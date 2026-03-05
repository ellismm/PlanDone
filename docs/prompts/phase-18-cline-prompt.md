# Cline Prompt — Phase 18 (Recurring Tasks & Cycle Rules)

Implement **Phase 18** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Enable reliable recurring task workflows with completion-gated cycle behavior and sync-safe instance generation.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Keep recurrence logic deterministic and idempotent.
3. Preserve existing permission and validation boundaries.
4. Avoid enterprise calendar complexity.

## Scope to implement now

1. Add recurrence model and settings on supported items.
2. Implement recurring instance generation with completion-gated behavior.
3. Prevent duplicate creation across retries/reconnects.
4. Add recurrence visibility/editing in item details.
5. Add/update tests for weekly gating and offline/sync edge cases.
6. Update docs and readiness checklist.

## Constraints

- No external calendar integrations.
- Keep recurrence options practical (daily/weekly/custom baseline).
- Keep migration path backwards-compatible where practical.

## Required output from you

1. Brief implementation plan.
2. Recurrence model and generation summary.
3. Code + tests + docs.
4. Edge-case notes (missed windows, duplicate suppression).
5. Phase-18 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can configure recurring tasks reliably.
- New instances are created according to cycle and completion rules.
- Duplicate generation is prevented under sync/offline transitions.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted recurrence lifecycle tests
