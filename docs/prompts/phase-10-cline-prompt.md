# Cline Prompt — Phase 10 (Quick Capture Inbox)

Implement **Phase 10** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Enable fast, low-friction capture of new work with a dedicated inbox + triage flow, while preserving local-first and permission safety.

## Non-negotiables

1. Keep local-first/offline-first guarantees.
2. Preserve existing role/permission enforcement.
3. Reuse canonical work-item model (no separate shadow item type).
4. Avoid broad redesign unrelated to capture/triage flow.

## Scope to implement now

1. Add a global quick-capture entry point.
2. Capture minimal fields rapidly (title + optional tags/context).
3. Add inbox state/view for untriaged items.
4. Add triage actions to assign board/column/type/parent.
5. Add/update tests for capture and triage behavior.
6. Update docs and readiness checklist for inbox workflow.

## Constraints

- Do not introduce AI dependency for baseline capture.
- Keep validation boundaries clear between capture and triage.
- Keep repository/controller contracts stable where practical.

## Required output from you

1. Brief implementation plan.
2. Capture/triage flow summary.
3. Code + tests + docs.
4. Tradeoff notes (speed vs structure).
5. Phase-10 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can add capture items quickly from workspace.
- Captures persist offline and survive sync cycles.
- Triage flow reliably converts captures into structured items.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted capture/triage widget tests
