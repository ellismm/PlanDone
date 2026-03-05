# Cline Prompt — Phase 16 (Hierarchy Visual Clarity)

Implement **Phase 16** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Improve hierarchy comprehension and planning density with optional color grouping and subtler parent-path display.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Reuse canonical hierarchy model and existing business rules.
3. Preserve permission enforcement in all views.
4. Keep accessibility and readability standards intact.

## Scope to implement now

1. Add optional hierarchy color grouping by top-level goal.
2. Support auto-assigned non-conflicting colors with manual override.
3. Add parent-path display preferences (visible/subtle/hidden on card).
4. Improve hierarchy view spacing/indentation to show more context per screen.
5. Ensure full hierarchy context remains available in item details.
6. Add/update tests for color stability, preferences, and rendering.
7. Update docs and readiness checklist.

## Constraints

- No redesign of hierarchy domain semantics.
- Keep color usage restrained and accessible.
- Avoid introducing heavy visual complexity.

## Required output from you

1. Brief implementation plan.
2. Visual hierarchy behavior summary.
3. Code + tests + docs.
4. Tradeoff notes (clarity vs visual noise).
5. Phase-16 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Hierarchy relationships are clearer at a glance.
- Users can choose parent-path visibility level.
- More hierarchy context fits on screen without losing usability.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted hierarchy rendering tests
