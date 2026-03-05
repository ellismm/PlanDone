# Phase 13 — Undo Safety Stack

## Objective

Increase daily-use confidence by making high-impact actions safely reversible
inside a short, clear undo window.

## Implemented

1. Added a reversible-operation contract in state layer:
   - `BoardUndoOperationKind` + `BoardUndoOperation`
   - `pendingBoardUndoOperationProvider`
   - `BoardController.undoWindow` (8s), stage helpers, and
     `undoPendingOperation()`
2. Added undo coverage for high-impact actions:
   - move (within board and cross-board)
   - re-parent
   - archive/unarchive
   - delete item (where supported)
3. Added delete/restore repository operations:
   - `deleteItem` with permission + child-integrity guard
   - `restoreItem` for undo recovery, including local persistence + outbox create
4. Added consistent undo UX:
   - unified snackbar with `Undo` action
   - timeout aligned with controller undo window
   - stale undo cleared when snackbar closes

## Reversible Model Summary

- Undo state is short-lived and local-first.
- Each staged undo operation stores enough inverse metadata to perform one
  deterministic rollback.
- Rollback executes through repository methods (no direct state mutation), so
  role/permission and validation checks remain enforced.

## Edge Cases and Behavior

- Undo vs sync race: rollback generates standard local mutations and outbox ops,
  so sync remains coherent; no side-channel mutation path is used.
- Timeout expiry: expired operations are rejected and cleared.
- Repeated actions: latest action replaces pending undo entry (single-depth undo).
- Delete safety: deleting an item with children is blocked to avoid hierarchy
  corruption.
- Restore fallback: if original parent/column is missing, restore falls back to a
  valid board state (root item / first column).

## Tests Added/Updated

- `test/features/board/presentation/board_controller_undo_test.dart`
  - undo move
  - undo archive toggle
  - undo delete
  - expired undo rejection
- `test/features/board/data/repositories/board_repository_impl_test.dart`
  - delete item outbox behavior
  - delete item child guard
  - restore item recreate behavior

## Acceptance Criteria Check

- [x] Supported high-impact actions can be undone reliably.
- [x] Undo does not corrupt local or synced state contract.
- [x] Undo UX clearly indicates temporary availability.
- [x] Tests/docs updated for the implemented scope.
