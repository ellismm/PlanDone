# Phase 5 — Workflow Semantics & Designated Columns

## Why this phase exists

Current behavior still derives workflow meaning from mutable column names (for example, “done”). This creates fragility and confusion when users rename columns. This phase introduces first-class workflow semantics while preserving customization.

## Scope

### In scope

- Add explicit workflow semantics to columns (for example `columnKind`, `isDoneState`, `isBlockedState`).
- Introduce designated starter columns/templates:
  - Planning
  - Backlog
  - Ready
  - In Progress
  - Blocked
  - Urgent
  - Review
  - Done
  - Cancelled
- Keep flexibility:
  - rename labels
  - reorder columns
  - hide/disable optional states
  - add custom columns
- Move completion behavior from name-based logic to semantic flags.
- Add board-level workflow configuration UI and persistence.

### Out of scope

- Full multi-view planning workbench (Phase 6).
- Cloud environment hardening (Phase 7).

## Key implementation targets

1. Extend domain/data model for semantic column behavior.
2. Add migration strategy for existing boards and legacy column names.
3. Replace all name-coupled behavior checks with semantic checks.
4. Add configuration UX for designated + custom columns.
5. Add tests for renamed columns and completed-state invariants.

## Risks and mitigations

- **Risk:** migration introduces incorrect column semantics for existing boards.  
  **Mitigation:** deterministic mapping + user-visible verification/edit step.
- **Risk:** too many required columns hurt simplicity.  
  **Mitigation:** designate required core states, keep others optional.

## Acceptance criteria

- Renaming “Done” no longer breaks completion behavior.
- Users can use designated defaults and still customize workflow.
- Board/column semantics are persisted and synced reliably.
- Tests cover migration + semantic behavior paths.

## Exit artifacts

- Workflow semantics model note.
- Migration and compatibility note for pre-semantic boards.
- Phase-5 checklist completion summary.

---

## Phase-5 implementation summary (current status)

### 1) Brief implementation plan

1. Introduce explicit semantic metadata on columns and workflow settings at board level.
2. Add designated starter workflow template while keeping legacy/default behavior intact.
3. Replace name-based done detection with semantic policy (`isDoneState` + inferred fallback).
4. Add board-level workflow controls + per-column semantics controls in UI/controller.
5. Ensure local store + sync payloads carry semantics and workflow settings.
6. Add migration-safe inference path for legacy boards and verify with tests.

### 2) Data model / migration summary

- `BoardColumn` semantics now include:
  - `kind` (`planning|backlog|ready|inProgress|blocked|urgent|review|done|cancelled|custom`)
  - `isDoneState`, `isBlockedState`, `isCancelledState`
  - `isDesignated`, `isEnabled`
- `Board` includes persisted `workflowSettings`:
  - `templateId`
  - `allowCustomColumns`
- Drift schema (v4) persists these fields in `board_columns` and `boards.workflow_settings_json`.
- Migration path for legacy boards:
  - Adds new semantic columns with safe defaults.
  - Best-effort semantic inference from legacy column names/ids.
  - Repository/local policy also performs legacy inference when semantics are missing.

### 3) Implemented code + tests + docs

- Domain/policy:
  - Semantic kinds and flags in column model.
  - `WorkflowSemanticsPolicy` for designated template, legacy inference, and semantic done-column resolution.
- Repository:
  - Completion logic now resolves done via semantic policy, not mutable names.
  - New board workflow operations:
    - `updateBoardWorkflowSettings`
    - `applyWorkflowTemplate`
    - `updateColumnSemantics`
  - Custom-column creation respects board workflow (`allowCustomColumns`).
- Presentation:
  - Board controller exposes workflow/semantics operations.
  - Board page includes:
    - workflow settings dialog (template + custom-column toggle)
    - per-column semantics dialog
    - semantic done handling in item cards.
  - Board configuration page adds predefined column creation flow:
    - selectable designated column types (planning/backlog/ready/in-progress/blocked/urgent/review/done/cancelled)
    - custom-name path only when `allowCustomColumns=true`
    - guarded handling when predefined set is exhausted and custom is disabled.
- Sync:
  - Firestore adapter now syncs `workflowSettings` and full column semantics payload.
  - Firestore hydrator now reads/writes board workflow settings + column semantics.
- Tests added/updated:
  - Repository tests for:
    - renamed done column behavior
    - designated template application
    - custom-column disallow behavior
    - semantic completion toggling.
  - Full `flutter test` run passing.

### 4) Edge-case notes

- **Renamed done column:** completion remains correct because done is semantic (`isDoneState`) and fallback inference, not column label.
- **Missing semantics (legacy/partial data):** policy applies deterministic inference and keeps behavior operational.
- **Legacy boards:** migration + runtime inference avoids hidden breaking changes and remains backward-compatible in practical use.

### 5) Phase-5 acceptance checklist results

- [x] Renaming columns no longer breaks done/completion behavior.
- [x] Designated + custom workflow paths both function.
- [x] Semantic behavior persists and syncs correctly.
- [x] Tests/docs are updated and coherent.
