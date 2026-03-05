# Cline Prompt — Phase 12 (Item Activity History)

Implement **Phase 12** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Improve day-to-day trust and traceability by adding meaningful, offline-safe activity history for core work-item changes.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Reuse canonical work-item model and mutation paths.
3. Preserve existing role/permission enforcement.
4. Avoid enterprise-heavy audit complexity outside core usage.

## Scope to implement now

1. Add activity event model with stable event types.
2. Emit events for high-value actions:
   - create/update
   - move/re-parent
   - archive/unarchive
   - complete/reopen
3. Persist activity locally with bounded retention.
4. Add readable activity timeline in item details.
5. Add/update tests for event emission correctness and ordering.
6. Update docs and readiness checklist.

## Constraints

- No broad compliance/audit platform expansion.
- Keep event payloads compact and useful for everyday users.
- Keep mutation contracts stable where practical.

## Required output from you

1. Brief implementation plan.
2. Activity model and retention summary.
3. Code + tests + docs.
4. Edge-case notes (offline ordering, noisy events, retention limits).
5. Phase-12 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can view clear item-level activity history.
- High-value actions consistently emit timeline events.
- History remains available in offline scenarios.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted activity/timeline tests
