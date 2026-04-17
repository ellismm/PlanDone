# Phase 4 — UX Foundation & Navigation Refactor

## Why this phase exists

PlanDone currently has strong core mechanics, but day-to-day usage still feels single-screen and modal-heavy. This phase establishes a multi-page structure so common actions are easier to find, faster to perform, and easier to maintain.

## Scope

### In scope

- Introduce route-based app shell/navigation for primary product areas.
- Split current board experience into dedicated surfaces:
  - **Board Workspace** (execution plus view-mode switching)
  - **Board Configuration** (board settings, members, validation/workflow settings)
  - **Board Insights** (board-neutral productivity metrics)
- Refactor large board UI into smaller, testable widgets/controllers.
- Improve discoverability and action grouping (less modal-only UX).

### Out of scope

- Full workflow semantics redesign (Phase 5).
- Deep planning/hierarchy multi-view suite (Phase 6).
- AI breakdown and automation (deferred to Phase 9).

## Key implementation targets

1. Add a stable navigation model (mobile + desktop friendly).
2. Move board-management actions out of overloaded top bar/menus.
3. Create dedicated board settings page with clear sections.
4. Preserve existing offline-first and permission behavior during refactor.
5. Add widget tests for key navigation and route guards.

## Risks and mitigations

- **Risk:** navigation refactor introduces regressions in board interactions.  
  **Mitigation:** preserve controller/repository contracts and add route + smoke tests.
- **Risk:** feature discoverability remains poor after split.  
  **Mitigation:** standardize IA labels and keep action grouping user-centric.

## Acceptance criteria

- App is no longer effectively a one-page workflow.
- Users can reach board configuration and alternate workspace views in <= 2 interactions.
- Existing board operations remain functional and permission-safe.
- Tests/docs are updated for new navigation structure.

## Exit artifacts

- Navigation map + route ownership notes.
- Updated UX architecture notes for page responsibilities.
- Phase-4 checklist completion summary.

## Implementation status (completed)

### Navigation map / route summary

- `/workspace` -> **Board Workspace**
  - Day-to-day board execution surface.
  - Item creation, movement, filtering, view switching, focus mode, sync actions.
- `/insights` -> **Board Insights**
  - Board-scoped accomplishments, momentum, health, and attention metrics.
- `/board-configuration` -> **Board Configuration**
  - Board-scope switching, board create/rename, column management, members, validation/workflow settings.
- `/planning` -> **Planning Entry Point**
  - Compatibility alias that redirects into `/workspace`.

### Page boundaries

- Workspace keeps execution and item operations.
- Workspace owns Kanban, Hierarchy, Backlog, and Focus as internal modes.
- Configuration centralizes governance/configuration actions.
- Insights provides board-neutral progress visibility without changing execution flow.

### Tradeoff notes (UX clarity vs complexity)

- **Improved clarity:** execution and planning views now live under one workspace home instead of splitting navigation between two destinations.
- **Added structural complexity:** the workspace shell now owns both route navigation and in-surface view switching.
- **Mitigation:** preserved existing providers/controllers/repository contracts and reused guard/permission behavior to avoid architecture churn.

### Acceptance checklist results

- [x] App is no longer effectively a one-page workflow.
- [x] Board configuration is reachable via dedicated UI surface.
- [x] Existing board operations and permission enforcement remain intact.
- [x] Tests/docs were updated for route and navigation behavior.
