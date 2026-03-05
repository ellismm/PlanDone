# Phase 15 — Item Details & Metadata System

## Why this phase exists

Users need a dedicated details experience to inspect item context without entering edit mode, and richer metadata for day-to-day planning.

## Scope

### In scope

- Dedicated read-first item details surface (open/view without immediate edit).
- Metadata model additions for planning-relevant fields:
  - start date
  - target end date
  - due date
  - created date
  - completed date
  - estimated effort
  - actual effort (where available)
- Configurable visibility/required settings for selected metadata fields.
- Auto-managed system fields (e.g., created/completed timestamps).

### Out of scope

- Heavy enterprise custom field builder.
- Time tracking with per-minute activity capture.

## Key implementation targets

1. Add details-view entry point from cards across supported views.
2. Extend canonical item model and persistence for new metadata fields.
3. Add board-level metadata display/required controls with sane defaults.
4. Implement automatic date updates for lifecycle events where deterministic.
5. Add tests for metadata persistence, field visibility/required behavior, and details rendering.

## Risks and mitigations

- **Risk:** metadata clutter reduces usability.  
  **Mitigation:** settings-driven visibility and grouped presentation.
- **Risk:** conflicting manual vs auto dates.  
  **Mitigation:** explicit precedence rules and UI hints.

## Acceptance criteria

- Users can view item details without entering edit mode.
- New metadata fields persist locally and sync through existing pipeline.
- Required/visible behavior works per board settings.
- Tests/docs are updated and coherent.

## Exit artifacts

- Metadata field behavior reference.
- Details view usage doc.
- Phase completion summary.

## Implementation Summary

- Added a read-first item details surface with metadata and activity timeline, plus an explicit Edit action.
- Extended canonical `WorkItem` metadata with:
  - `targetEndAt`
  - `estimatedEffortMinutes`
  - `actualEffortMinutes`
  Existing canonical fields continue to be used for:
  - `startAt`
  - `dueAt`
  - `createdAt`
  - `completedAt`
- Added board-level metadata visibility/required controls via `BoardValidationSettings`.
- Implemented deterministic auto-managed lifecycle behavior:
  - `createdAt` set on create and retained across updates/moves.
  - `completedAt` set/cleared based on done-state column semantics.
  - `startAt` auto-populates when an item first moves into an in-progress column.
- Persisted metadata across local Drift storage and Firestore sync/hydration paths.
- Added/updated tests for:
  - metadata persistence in repository updates
  - required metadata validation behavior
  - Firestore hydration of metadata fields
  - Firestore sync merge/preservation behavior for metadata fields

## Edge-Case Rules (Manual vs Auto)

- Manual metadata edits win unless a deterministic lifecycle transition applies.
- Done-state transitions continue to own `completedAt`.
- In-progress first-entry transition can set `startAt` only when currently unset.
