# Cline Prompt — Phase 6 (Planning Views + Hierarchy Management)

Implement **Phase 6** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Deliver a multi-view planning workspace that supports top-down strategy and bottom-up execution using the same canonical hierarchy model.

## Non-negotiables

1. Keep local-first/offline-first guarantees.
2. Reuse a single canonical work-item model across views.
3. Preserve role/permission enforcement in all views.
4. Avoid feature drift by sharing filter/query logic.

## Scope to implement now

1. Add switchable board views:
   - Kanban
   - Hierarchy
   - Backlog
   - Focus
2. Add hierarchy operations:
   - re-parent
   - bulk move/archive/tag changes
   - type/tag/state filtering
3. Ensure view continuity (selection/filter context retained when switching).
4. Add/update tests for hierarchy correctness and bulk operations.
5. Update docs for view behaviors and planning workflows.

## Constraints

- Do not duplicate business rules per view.
- Keep performance acceptable on large boards.
- Keep UX clear and non-enterprise-heavy.

## Required output from you

1. Brief implementation plan.
2. View architecture summary.
3. Code + tests + docs.
4. Performance/complexity tradeoff notes.
5. Phase-6 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can switch views without losing context.
- Hierarchy operations behave consistently across views.
- Bulk operations preserve data integrity.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted performance checks on large board fixtures
