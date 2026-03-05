# Cline Prompt — Phase 4 (UX Foundation + Navigation Refactor)

Implement **Phase 4** for PlanDone, aligned to the revised usability-first roadmap.

## Objective

Evolve PlanDone from an effectively single-page workflow into a structured, multi-page product with clear navigation and dedicated configuration surfaces.

## Non-negotiables

1. Do **not** redesign core architecture.
2. Preserve layering: `UI -> State -> Domain -> Repository -> Data Sources`.
3. Keep local DB as source of truth.
4. Preserve existing role/permission enforcement.
5. Keep offline-first behavior intact.

## Scope to implement now

1. Add route-based app shell/navigation for primary areas.
2. Establish dedicated page boundaries:
   - Board Workspace
   - Board Configuration
   - Planning entry point (full views in later phase)
3. Refactor board-page monolith into smaller components.
4. Improve discoverability and grouping of common actions.
5. Add/update tests for navigation and key route flows.
6. Update docs to reflect new IA/navigation model.

## Constraints

- No broad feature expansion outside navigation/UX foundation.
- Avoid breaking repository/controller contracts during refactor.
- Keep behavior parity for existing board operations.

## Required output from you

1. Brief implementation plan.
2. Code + tests + docs.
3. Navigation map / route summary.
4. Tradeoff notes (UX clarity vs complexity).
5. Phase-4 acceptance checklist results.

## Acceptance criteria (must satisfy)

- App is no longer effectively a single-page experience.
- Board configuration is reachable via dedicated UI surface.
- Core board operations still work and permissions remain enforced.
- Tests/docs are updated and coherent.

## Validation commands

- `flutter test`
- (optional) targeted widget/navigation tests
