# Cline Prompt — Phase 11 (Saved Filter Presets)

Implement **Phase 11** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Reduce repetitive planning setup by allowing users to save and quickly reapply filter presets across supported views.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Preserve existing filter/query logic as canonical source.
3. Keep user-scoped data boundaries clear.
4. Avoid introducing enterprise-heavy query complexity.

## Scope to implement now

1. Add preset model for current filter/search/scope context.
2. Add preset CRUD: save/apply/rename/update/delete.
3. Persist presets per user locally (and sync-compatible if supported).
4. Integrate preset application into workspace/planning flows.
5. Add/update tests for preset persistence and correctness.
6. Update docs and readiness checklist.

## Constraints

- No broad feature expansion outside preset functionality.
- Keep UI interaction lightweight and discoverable.
- Keep backwards compatibility for existing filter behavior.

## Required output from you

1. Brief implementation plan.
2. Preset model summary.
3. Code + tests + docs.
4. Edge-case notes (missing/legacy fields).
5. Phase-11 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Users can save/apply presets without losing context unexpectedly.
- Presets persist correctly per user.
- Presets work in supported views and fail gracefully where unsupported.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted filter/preset tests
