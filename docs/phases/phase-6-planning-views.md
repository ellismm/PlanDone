# Phase 6 — Planning Views & Hierarchy Management

## Why this phase exists

Users need multiple ways to plan, not only a kanban lane view. This phase adds first-class planning views so the hierarchy (Goal/Project/Task/Action) is practical for strategy, execution, and review.

## Scope

### In scope

- Add multi-view board workspace with switchable views:
  - **Kanban View** (execution flow)
  - **Hierarchy View** (tree/planning)
  - **Backlog View** (prioritized queue)
  - **Focus View** (urgent/blocked/due-soon)
- Add richer hierarchy operations:
  - re-parenting
  - bulk move/archive/tag updates
  - quick filters by type/owner/tag/state
- Add board/column/task configuration entry points within planning flows.

### Out of scope

- Cloud environment hardening and ops maturity (Phase 7).
- AI-assisted generation and automation (Phase 9).

## Key implementation targets

1. Introduce extensible view-state architecture per board.
2. Reuse shared query/filter logic across views to avoid drift.
3. Ensure each view remains local-first and sync-compatible.
4. Add UX affordances for rapid top-down planning and bottom-up execution.
5. Add tests for hierarchy consistency after bulk operations.

## Risks and mitigations

- **Risk:** multiple views create conflicting item representations.  
  **Mitigation:** single canonical item model + shared projection helpers.
- **Risk:** performance degradation on large boards.  
  **Mitigation:** pagination/virtualization and view-specific query optimization.

## Acceptance criteria

- Users can switch views without losing context.
- Hierarchy operations behave consistently across views.
- Planning workflows are faster and clearer than single-view baseline.
- Tests/docs cover view behavior and hierarchy operations.

## Exit artifacts

- Planning-views UX specification.
- Hierarchy operation rules note.
- Phase-6 checklist completion summary.

---

## Phase-6 implementation summary (current status)

### 1) Brief implementation plan

1. Keep one canonical board/item model and render multiple views from shared filters.
2. Expose view switching directly in workspace while retaining filter/selection context.
3. Ensure hierarchy operations (re-parent + bulk actions) are available and permission-guarded.
4. Reuse shared visibility/state/tag/date filter logic across kanban/hierarchy/backlog/focus.
5. Add repository and widget tests, then document behavior and checklist status.

### 2) View architecture summary

- View mode is state-driven via `boardPlanningViewProvider`:
  - `kanban`, `hierarchy`, `backlog`, `focus`
- Shared query path:
  - `_isVisibleInCurrentModes(...)` + `_sharedVisibleItems(...)`
  - same type/state/tag/date/search/focus predicates reused across views
- Rendering path:
  - Workspace route renders kanban or `_buildAlternativeView(...)` based on selected planning view.
- Continuity:
  - selected items, focus context, filters, and view mode are provider-backed and persist across view switches.

### 3) Implemented code + tests + docs

- Workspace view switch + shared filtering/bulk operations:
  - `board_page.dart`
- Controller/provider continuity for view/filter/selection state:
  - `board_controller.dart`
- Repository validation for hierarchy and bulk integrity:
  - `board_repository_impl_test.dart`:
    - `reparentItem updates parent linkage without mutating other fields`
    - `bulkUpdateItems moves, archives, and edits tags consistently`
- Full test suite run:
  - `flutter test` passing

### 4) Performance/complexity tradeoff notes

- **Pros:** one shared visibility/filter pipeline avoids view-rule drift and reduces maintenance overhead.
- **Cost:** filtering/ordering is computed in UI on each build, which is simple and coherent but can add work on very large boards.
- **Mitigation:** logic is centralized and deterministic, enabling later targeted optimizations (memoization/pagination) without changing behavior contracts.

### 5) Phase-6 acceptance checklist results

- [x] Users can switch views without losing context.
- [x] Hierarchy operations behave consistently across views.
- [x] Bulk operations preserve data integrity.
- [x] Tests/docs are updated and coherent.
