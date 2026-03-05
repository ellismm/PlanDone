# Cline Prompt — Phase 15 (Item Details & Metadata System)

Implement **Phase 15** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Add a dedicated item details experience and richer metadata model so users can inspect context without entering edit mode and plan with better signals.

## Non-negotiables

1. Preserve local-first/offline-first guarantees.
2. Reuse a single canonical work-item model.
3. Preserve role/permission and board validation boundaries.
4. Keep metadata complexity practical for daily use.

## Scope to implement now

1. Add read-first item details surface (view without forced edit).
2. Add metadata fields: start date, target end date, due date, created date, completed date, estimated effort, actual effort baseline.
3. Add board-level settings for metadata visibility/required behavior.
4. Implement deterministic auto-managed fields (e.g., created/completed timestamps).
5. Add/update tests for persistence, settings behavior, and details rendering.
6. Update docs and readiness checklist.

## Constraints

- No large custom-fields framework.
- Keep schema/data migration backwards-compatible where practical.
- Avoid breaking repository/controller contracts.

## Required output from you

1. Brief implementation plan.
2. Metadata model/migration summary.
3. Code + tests + docs.
4. Edge-case notes (manual vs auto date precedence).
5. Phase-15 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can open a details view without entering edit mode.
- Metadata fields persist and sync correctly.
- Visibility/required settings behave predictably per board.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted metadata/details tests
