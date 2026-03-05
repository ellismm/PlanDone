# Phase 10 — Quick Capture Inbox

## Why this phase exists

Daily use improves when capture friction is near zero. Users should be able to quickly record ideas/actions first, then triage with full context later.

## Scope

### In scope

- Global quick-capture entry point from primary app surfaces.
- Minimal capture payload (title + optional quick tags).
- Inbox queue for untriaged items.
- Triage flow to assign:
  - item type
  - board
  - column
  - optional parent
- Offline-first capture behavior and sync compatibility.

### Out of scope

- AI-assisted capture parsing.
- Broad redesign of board/planning views.

## Key implementation targets

1. Add a canonical inbox status/state to work-item flow.
2. Add quick-capture UI that works in <=2 interactions.
3. Add triage UI for bulk/individual assignment.
4. Ensure captured items remain local-first and permission-safe.
5. Add tests for capture + triage + offline behavior.

## Risks and mitigations

- **Risk:** quick capture bypasses validation quality.  
  **Mitigation:** defer strict validation to triage/activation transitions.
- **Risk:** inbox becomes cluttered.  
  **Mitigation:** clear status markers + bulk triage actions.

## Acceptance criteria

- Quick capture is fast and available from workspace context.
- Captured items are recoverable and triageable.
- Offline capture remains reliable.
- Tests/docs are updated and coherent.

## Exit artifacts

- Inbox capture/triage behavior docs.
- Tests for capture and triage reliability.
- Phase completion summary.

## Implemented IA notes

- Workspace app bar includes a `Quick capture` action.
- Workspace includes an inbox surface toggle (Board vs Inbox).
- Inbox items are hidden from standard board/planning lists until triaged.
- Triage action supports assigning board, column, type, and optional parent.
