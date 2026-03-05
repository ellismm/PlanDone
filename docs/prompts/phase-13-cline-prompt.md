# Cline Prompt — Phase 13 (Undo Safety Stack)

Implement **Phase 13** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Increase daily-use confidence by making high-impact actions safely reversible within a clear undo window.

## Non-negotiables

1. Preserve local-first/offline-first guarantees.
2. Keep board/item data integrity intact across undo operations.
3. Preserve role/permission enforcement for reversible actions.
4. Avoid building unlimited history/time-travel scope.

## Scope to implement now

1. Define reversible-operation contract for supported actions.
2. Add undo support for selected high-impact actions:
   - archive/unarchive
   - move/re-parent
   - delete where supported
3. Add short-lived undo state handling in local-first flow.
4. Add consistent undo UX (snackbar/banner with clear timeout).
5. Ensure outbox/sync interactions remain coherent after undo.
6. Add/update tests for undo edge cases.
7. Update docs and readiness checklist.

## Constraints

- No broad redo/time-machine framework expansion.
- Keep undo behavior predictable and clearly communicated.
- Avoid hidden behavioral regressions in existing board flows.

## Required output from you

1. Brief implementation plan.
2. Reversible operation model summary.
3. Code + tests + docs.
4. Edge-case notes (undo vs sync race, timeout expiry, repeated actions).
5. Phase-13 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Supported high-impact actions can be undone reliably.
- Undo does not corrupt local or synced state.
- Undo UX is clear about availability window and outcome.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted undo/sync interaction tests
