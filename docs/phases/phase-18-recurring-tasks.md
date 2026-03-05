# Phase 18 — Recurring Tasks & Cycle Rules

## Why this phase exists

Many real workflows are recurring. Users need recurring-item support that respects completion state and avoids creating noisy duplicates.

## Scope

### In scope

- Recurrence settings for supported items (daily/weekly/custom cadence baseline).
- Rule: next instance creation depends on prior instance completion policy.
- Option to skip or defer missed occurrences.
- Local-first recurrence scheduling and sync-safe operation IDs.
- Visibility of recurrence state in item details.

### Out of scope

- Full calendar suite or external calendar sync.
- Complex RRULE edge-case parity with enterprise calendar systems.

## Key implementation targets

1. Define recurring configuration model and canonical rule evaluation.
2. Implement instance-generation engine with completion-gated behavior.
3. Ensure no duplicate instance creation during reconnect/retry cycles.
4. Add UI for enabling/editing recurrence in item details.
5. Add tests for weekly gating rule, skipped windows, and offline sync edge cases.

## Risks and mitigations

- **Risk:** duplicate instances under sync retries.  
  **Mitigation:** idempotent recurrence keys and deterministic evaluation windows.
- **Risk:** confusing recurrence controls.  
  **Mitigation:** plain-language recurrence summaries in UI.

## Acceptance criteria

- Recurring tasks can be configured and run reliably.
- Completion-gated recurrence behavior works as expected.
- Duplicate generation is prevented across offline/online transitions.
- Tests/docs are updated and coherent.

## Exit artifacts

- Recurrence rules reference.
- Tests for recurrence lifecycle and sync behavior.
- Phase completion summary.
