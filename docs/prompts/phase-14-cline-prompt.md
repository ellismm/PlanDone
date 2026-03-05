# Cline Prompt — Phase 14 (Card Density & Readability)

Implement **Phase 14** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Improve daily scanability by making column and item titles more visible and reducing card crowding while preserving usability on mobile.

## Non-negotiables

1. Preserve local-first/offline-first behavior.
2. Keep architecture layering unchanged (`UI -> State -> Domain -> Repository -> Data Sources`).
3. Preserve existing role/permission enforcement.
4. Avoid broad feature expansion outside readability and density polish.

## Scope to implement now

1. Add card density controls (compact/comfortable baseline).
2. Improve title visibility and truncation behavior on columns/cards.
3. Reduce non-essential card chrome and move secondary context to details surfaces.
4. Ensure hierarchy and board views show more items per screen without harming touch targets.
5. Add/update widget tests for density and truncation behavior.
6. Update docs and readiness checklist.

## Constraints

- No broad redesign of core workflows.
- Keep touch target accessibility acceptable.
- Preserve behavior parity for board operations.

## Required output from you

1. Brief implementation plan.
2. Readability and density summary.
3. Code + tests + docs.
4. Tradeoff notes (density vs touch comfort).
5. Phase-14 acceptance checklist results.

## Acceptance criteria (must satisfy)

- Titles are more readable with less frequent truncation pain.
- Users can switch density to view more plan context.
- Core card interactions still work reliably on mobile.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted widget tests for card rendering
