# Cline Prompt — Phase 5 (Workflow Semantics + Designated Columns)

Implement **Phase 5** for PlanDone, aligned to the revised roadmap.

## Objective

Replace fragile name-based workflow behavior with explicit column semantics while keeping user flexibility to customize columns.

## Non-negotiables

1. Preserve offline-first and local-first architecture.
2. Do **not** rely on mutable column names for core behavior (e.g., done state).
3. Preserve existing permissions and board validation boundaries.
4. Keep customization available (rename/reorder/custom columns).

## Scope to implement now

1. Add semantic column behavior model (state/kind flags).
2. Add designated starter workflow template(s):
   - planning, backlog, ready, in progress, blocked, urgent, review, done, cancelled
3. Replace name-coupled completion logic with semantic state logic.
4. Add board-level workflow configuration controls.
5. Add migration path for existing boards.
6. Add/update tests and docs for semantic behavior.

## Constraints

- Keep schema/data migration backwards-compatible where practical.
- Avoid hidden breaking changes to existing boards.
- Keep implementation simple enough for everyday use.

## Required output from you

1. Brief implementation plan.
2. Data model/migration summary.
3. Code + tests + docs.
4. Edge-case notes (renamed done, missing semantics, legacy boards).
5. Phase-5 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Renaming columns no longer breaks done/completion behavior.
- Designated + custom workflow paths both function.
- Semantic behavior persists and syncs correctly.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) migration-focused tests
